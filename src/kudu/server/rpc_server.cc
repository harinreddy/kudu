// Licensed to the Apache Software Foundation (ASF) under one
// or more contributor license agreements.  See the NOTICE file
// distributed with this work for additional information
// regarding copyright ownership.  The ASF licenses this file
// to you under the Apache License, Version 2.0 (the
// "License"); you may not use this file except in compliance
// with the License.  You may obtain a copy of the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing,
// software distributed under the License is distributed on an
// "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
// KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations
// under the License.

#include "kudu/server/rpc_server.h"

#include <functional>
#include <memory>
#include <ostream>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

#include <gflags/gflags.h>
#include <glog/logging.h>

#include "kudu/gutil/casts.h"
#include "kudu/gutil/macros.h"
#include "kudu/gutil/ref_counted.h"
#include "kudu/gutil/strings/join.h"
#include "kudu/gutil/strings/substitute.h"
#include "kudu/rpc/acceptor_pool.h" // IWYU pragma: keep
#include "kudu/rpc/messenger.h"     // IWYU pragma: keep
#include "kudu/rpc/rpc_service.h"
#include "kudu/rpc/service_if.h"
#include "kudu/rpc/service_pool.h"
#include "kudu/util/flag_tags.h"
#include "kudu/util/flag_validators.h"
#include "kudu/util/net/net_util.h"
#include "kudu/util/net/sockaddr.h"
#include "kudu/util/status.h"

using kudu::rpc::AcceptorPool;
using kudu::rpc::Messenger;
using kudu::rpc::ServiceIf;
using std::shared_ptr;
using std::string;
using std::unique_ptr;
using std::vector;
using strings::Substitute;

DEFINE_string(rpc_bind_addresses, "0.0.0.0",
              "Comma-separated list of addresses to bind to for RPC connections. "
              "Currently, ephemeral ports (i.e. port 0) are not allowed.");
TAG_FLAG(rpc_bind_addresses, stable);

DEFINE_string(rpc_advertised_addresses, "",
              "Comma-separated list of addresses to advertise externally for RPC "
              "connections. Ephemeral ports (i.e. port 0) are not allowed. This "
              "should be configured when the locally bound RPC addresses "
              "specified in --rpc_bind_addresses are not externally resolvable, "
              "for example, if Kudu is deployed in a container.");
TAG_FLAG(rpc_advertised_addresses, advanced);

DEFINE_string(rpc_proxied_addresses, "",
              "Comma-separated list of addresses to accept RPC requests "
              "forwarded from external networks (possibly, via a TCP proxy). "
              "These are RPC endpoints in the inner network to handle RPC "
              "requests forwarded/proxied from outside networks; "
              "they are orthogonal to --rpc_advertised_addresses, so these "
              "can be used in containerized environments behind a firewall.");
TAG_FLAG(rpc_proxied_addresses, advanced);
TAG_FLAG(rpc_proxied_addresses, experimental);

DEFINE_string(rpc_proxy_advertised_addresses, "",
              "This server's RPC endpoints exposed to the external network via "
              "a TCP proxy. It's assumed that RPCs sent by a Kudu client from "
              "the external network are forwarded/proxied to the RPC endpoint "
              "in the inner cluster's network, where the latter is specified "
              "by the --rpc_proxied_addresses flag.");
TAG_FLAG(rpc_proxy_advertised_addresses, advanced);
TAG_FLAG(rpc_proxy_advertised_addresses, experimental);

DEFINE_int32(rpc_num_acceptors_per_address, 1,
             "Number of RPC acceptor threads for each bound address");
TAG_FLAG(rpc_num_acceptors_per_address, advanced);

DEFINE_int32(rpc_num_service_threads, 10,
             "Number of RPC worker threads to run");
TAG_FLAG(rpc_num_service_threads, advanced);

DEFINE_int32(rpc_service_queue_length, 50,
             "Default length of queue for incoming RPC requests");
TAG_FLAG(rpc_service_queue_length, advanced);

DEFINE_bool(rpc_server_allow_ephemeral_ports, false,
            "Allow binding to ephemeral ports. This can cause problems, so currently "
            "only allowed in tests.");
TAG_FLAG(rpc_server_allow_ephemeral_ports, unsafe);

DEFINE_bool(rpc_reuseport, false,
            "Whether to set the SO_REUSEPORT option on listening RPC sockets.");
TAG_FLAG(rpc_reuseport, experimental);

namespace {

bool ValidateProxyAddresses()  {
  if ((FLAGS_rpc_proxied_addresses.empty() &&
       !FLAGS_rpc_proxy_advertised_addresses.empty()) ||
      (!FLAGS_rpc_proxied_addresses.empty() &&
       FLAGS_rpc_proxy_advertised_addresses.empty())) {
    LOG(ERROR) << Substitute(
        "--rpc_proxy_advertised_addresses and --rpc_proxied_addresses should "
        "be either both set or both unset");
    return false;
  }
  return true;
}
GROUP_FLAG_VALIDATOR(proxy_addresses, ValidateProxyAddresses);

} // anonymous namespace


namespace kudu {

RpcServerOptions::RpcServerOptions()
    : rpc_bind_addresses(FLAGS_rpc_bind_addresses),
      rpc_advertised_addresses(FLAGS_rpc_advertised_addresses),
      rpc_proxied_addresses(FLAGS_rpc_proxied_addresses),
      rpc_proxy_advertised_addresses(FLAGS_rpc_proxy_advertised_addresses),
      num_acceptors_per_address(FLAGS_rpc_num_acceptors_per_address),
      num_service_threads(FLAGS_rpc_num_service_threads),
      default_port(0),
      service_queue_length(FLAGS_rpc_service_queue_length),
      rpc_reuseport(FLAGS_rpc_reuseport) {
}

RpcServer::RpcServer(RpcServerOptions opts)
    : server_state_(UNINITIALIZED), options_(std::move(opts)) {}

RpcServer::~RpcServer() {
  Shutdown();
}

string RpcServer::ToString() const {
  if (PREDICT_FALSE(UNINITIALIZED == server_state_)) {
    return options_.rpc_bind_addresses;
  }

  return JoinMapped(rpc_bind_addresses_,
                    [] (const Sockaddr& sock_addr) { return sock_addr.ToString(); },
                    ",");
}

Status RpcServer::Init(const shared_ptr<Messenger>& messenger) {
  CHECK_EQ(server_state_, UNINITIALIZED);
  messenger_ = messenger;

  constexpr auto addr_check_fn = [] (const vector<Sockaddr>& addresses,
                                     bool allow_ephemeral_ports) {
    for (const Sockaddr& addr : addresses) {
      if (!addr.is_ip()) {
        continue;
      }

      if (IsPrivilegedPort(addr.port())) {
        LOG(WARNING) << Substitute(
            "may be unable to bind to privileged port for address $0",
            addr.ToString());
      }

      // Currently, we can't support binding to ephemeral ports outside of
      // unit tests, because consensus caches RPC ports of other servers
      // across restarts. See KUDU-334.
      if (addr.port() == 0 && !allow_ephemeral_ports) {
        LOG(FATAL) << Substitute(
            "binding to ephemeral ports not supported "
            "(RPC address configured to $0)", addr.ToString());
      }
    }
  };

  const bool allow_ephemeral_ports = FLAGS_rpc_server_allow_ephemeral_ports;
  RETURN_NOT_OK(ParseAddressList(options_.rpc_bind_addresses,
                                 options_.default_port,
                                 &rpc_bind_addresses_));
  addr_check_fn(rpc_bind_addresses_, allow_ephemeral_ports);

  if (!options_.rpc_advertised_addresses.empty()) {
    RETURN_NOT_OK(ParseAddressList(options_.rpc_advertised_addresses,
                                   options_.default_port,
                                   &rpc_advertised_addresses_));

    for (const Sockaddr& addr : rpc_advertised_addresses_) {
      if (addr.port() == 0) {
        LOG(FATAL) << "Advertising an ephemeral port is not supported (RPC advertised address "
                   << "configured to " << addr.ToString() << ")";
      }
    }
  }

  if (!options_.rpc_proxied_addresses.empty()) {
    RETURN_NOT_OK(ParseAddressList(options_.rpc_proxied_addresses,
                                   options_.default_port,
                                   &rpc_proxied_addresses_));
    addr_check_fn(rpc_proxied_addresses_, allow_ephemeral_ports);
  }

  if (!options_.rpc_proxy_advertised_addresses.empty()) {
    vector<HostPort> host_ports;
    RETURN_NOT_OK(HostPort::ParseStrings(
        options_.rpc_proxy_advertised_addresses, options_.default_port, &host_ports));
    if (host_ports.empty()) {
      return Status::InvalidArgument("no proxy advertised address specified");
    }
    rpc_proxy_advertised_hostports_ = std::move(host_ports);
  }

  server_state_ = INITIALIZED;
  return Status::OK();
}

Status RpcServer::RegisterService(unique_ptr<rpc::ServiceIf> service) {
  CHECK(server_state_ == INITIALIZED ||
        server_state_ == BOUND) << "bad state: " << server_state_;
  scoped_refptr<rpc::ServicePool> service_pool =
    new rpc::ServicePool(std::move(service), messenger_->metric_entity(),
                         options_.service_queue_length);
  RETURN_NOT_OK(service_pool->Init(options_.num_service_threads));
  auto* service_pool_raw_ptr = service_pool.get();
  service_pool->set_too_busy_hook([this, service_pool_raw_ptr]() {
      if (too_busy_hook_) {
        too_busy_hook_(service_pool_raw_ptr);
      }
    });
  return messenger_->RegisterService(service_pool->service_name(), service_pool);
}

Status RpcServer::AddBindAddress(const Sockaddr& addr) {
  CHECK_EQ(server_state_, INITIALIZED) << "must add bind addresses between Init() and Bind()";
  rpc_bind_addresses_.emplace_back(addr);
  return Status::OK();
}

Status RpcServer::Bind() {
  CHECK_EQ(server_state_, INITIALIZED);

  // Create the Acceptor pools (one per bind address)
  vector<shared_ptr<AcceptorPool> > new_acceptor_pools;
  // Create the AcceptorPool for each bind address.
  for (const Sockaddr& bind_addr : rpc_bind_addresses_) {
    shared_ptr<rpc::AcceptorPool> pool;
    RETURN_NOT_OK(messenger_->AddAcceptorPool(bind_addr, &pool));
    new_acceptor_pools.emplace_back(std::move(pool));
  }

  // Create the AcceptorPool for each address for proxied RPCs.
  {
    vector<Sockaddr> bound_rpc_proxied_addresses;
    bound_rpc_proxied_addresses.reserve(rpc_proxied_addresses_.size());
    for (const Sockaddr& bind_addr : rpc_proxied_addresses_) {
      shared_ptr<rpc::AcceptorPool> pool;
      RETURN_NOT_OK(messenger_->AddAcceptorPool(bind_addr, &pool));
      new_acceptor_pools.emplace_back(std::move(pool));
      Sockaddr bound_addr;
      RETURN_NOT_OK(new_acceptor_pools.back()->GetBoundAddress(&bound_addr));
      bound_rpc_proxied_addresses.emplace_back(std::move(bound_addr));
    }
    // The proxied addresses might be specified with a wildcard port,
    // so here the bound addresses with actually bound ports are stored.
    rpc_proxied_addresses_ = std::move(bound_rpc_proxied_addresses);
  }

  acceptor_pools_.swap(new_acceptor_pools);

  server_state_ = BOUND;
  return Status::OK();
}

Status RpcServer::Start() {
  if (server_state_ == INITIALIZED) {
    RETURN_NOT_OK(Bind());
  }
  CHECK_EQ(server_state_, BOUND);
  server_state_ = STARTED;

  for (const shared_ptr<AcceptorPool>& pool : acceptor_pools_) {
    RETURN_NOT_OK(pool->Start(options_.num_acceptors_per_address));
  }

  vector<Sockaddr> bound_addrs;
  RETURN_NOT_OK(GetBoundAddresses(&bound_addrs));
  string bound_addrs_str;
  for (const Sockaddr& bind_addr : bound_addrs) {
    if (!bound_addrs_str.empty()) bound_addrs_str += ", ";
    bound_addrs_str += bind_addr.ToString();
  }
  LOG(INFO) << "RPC server started. Bound to: " << bound_addrs_str;
  messenger_->SetServicesRegistered();

  return Status::OK();
}

void RpcServer::Shutdown() {
  for (const shared_ptr<AcceptorPool>& pool : acceptor_pools_) {
    pool->Shutdown();
  }
  acceptor_pools_.clear();

  if (messenger_) {
    messenger_->UnregisterAllServices();
  }
}

Status RpcServer::GetBoundAddresses(vector<Sockaddr>* addresses) const {
  if (server_state_ != BOUND &&
      server_state_ != STARTED) {
    return Status::ServiceUnavailable(Substitute("bad state: $0", server_state_));
  }
  for (const shared_ptr<AcceptorPool>& pool : acceptor_pools_) {
    Sockaddr bound_addr;
    RETURN_NOT_OK_PREPEND(pool->GetBoundAddress(&bound_addr),
                          "Unable to get bound address from AcceptorPool");
    addresses->emplace_back(std::move(bound_addr));
  }
  return Status::OK();
}

Status RpcServer::GetBoundHostPorts(vector<HostPort>* hostports) const {
  vector<Sockaddr> addrs;
  RETURN_NOT_OK_PREPEND(GetBoundAddresses(&addrs), "could not get bound RPC addresses");
  return HostPortsFromAddrs(addrs, hostports);
}

Status RpcServer::GetAdvertisedAddresses(vector<Sockaddr>* addresses) const {
  if (server_state_ != BOUND &&
      server_state_ != STARTED) {
    return Status::ServiceUnavailable(Substitute("bad state: $0", server_state_));
  }

  if (!rpc_advertised_addresses_.empty()) {
    *addresses = rpc_advertised_addresses_;
    return Status::OK();
  }

  vector<Sockaddr> tmp;
  RETURN_NOT_OK(GetBoundAddresses(&tmp));
  // Remove addresses that are dedicated to serve proxied RPCs. Those should
  // not be advertised to clients: a client isn't supposed to send RPCs to
  // those endpoints directly, but that's where the requests are proxied to.
  addresses->reserve(tmp.size());
  for (auto& addr : tmp) {
    if (!IsAddrOneOf(addr, rpc_proxied_addresses_)) {
      addresses->emplace_back(std::move(addr));
    }
  }
  return Status::OK();
}

Status RpcServer::GetAdvertisedHostPorts(vector<HostPort>* hostports) const {
  vector<Sockaddr> addrs;
  RETURN_NOT_OK_PREPEND(GetAdvertisedAddresses(&addrs), "could not get bound RPC addresses");
  return HostPortsFromAddrs(addrs, hostports);
}

const vector<HostPort>& RpcServer::GetProxyAdvertisedHostPorts() const {
  DCHECK_NE(UNINITIALIZED, server_state_);
  return rpc_proxy_advertised_hostports_;
}

const vector<Sockaddr>& RpcServer::GetRpcProxiedAddresses() const {
  DCHECK_NE(UNINITIALIZED, server_state_);
  return rpc_proxied_addresses_;
}

const rpc::ServicePool* RpcServer::service_pool(const string& service_name) const {
  return down_cast<rpc::ServicePool*>(messenger_->rpc_service(service_name).get());
}

} // namespace kudu
