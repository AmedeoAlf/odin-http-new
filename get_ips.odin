#+private file
package http

import "core:c"
import "core:net"
import "core:strings"
import "core:sys/linux"
foreign import libc "system:c"

@(private)
Ip :: struct {
  addr:   string,
  ifname: string,
}

@(private)
get_ips :: proc(allocator := context.temp_allocator) -> []Ip {
  // addrs, err := net.enumerate_interfaces()
  // fmt.println(addrs, err)
  ifaddrs: ^ifaddrs
  ifaddrs_err := getifaddrs(&ifaddrs)
  if ifaddrs_err != .NONE do return nil
  defer freeifaddrs(ifaddrs)

  ips := make([dynamic]Ip, allocator)
  for curr := ifaddrs; curr != nil; curr = curr.ifa_next {
    (.IFF_UP in curr.ifa_flags) or_continue
    (.IFF_LOOPBACK not_in curr.ifa_flags) or_continue
    ip: Ip
    #partial switch curr.ifa_addr.sa_family {
    case .INET:
      ip.addr = net.address_to_string(
        net.IP4_Address(static_slice(&curr.ifa_addr.sa_data, 2, 6)),
        allocator,
      )
    case .INET6:
      ip.addr = net.address_to_string(
        net.IP6_Address(static_slice(&curr.ifa_addr.sa_data, 2, 10)),
        allocator,
      )
    case:
      continue
    }
    ip.ifname = strings.clone_from_cstring(curr.ifa_name, allocator)
    append(&ips, ip)
  }
  return ips[:]
}

sockaddr :: struct {}
ifaddrs :: struct {
  ifa_next:    ^ifaddrs, /* Next item in list */
  ifa_name:    cstring, /* Name of interface */
  ifa_flags:   SIOCSIFFLAGS,
  ifa_addr:    ^linux.Sock_Addr, /* Address of interface */
  ifa_netmask: ^linux.Sock_Addr, /* Netmask of interface */
  ifa_ifu:     ^linux.Sock_Addr,
  //     union {
  //         struct sockaddr *ifu_broadaddr;
  //                          /* Broadcast address of interface */
  //         struct sockaddr *ifu_dstaddr;
  //                          /* Point-to-point destination address */
  //     } ifa_ifu;
  // #define              ifa_broadaddr ifa_ifu.ifu_broadaddr
  // #define              ifa_dstaddr   ifa_ifu.ifu_dstaddr
  ifa_data:    rawptr, /* Address-specific data */
}

foreign libc {
  getifaddrs :: proc "c" (ifap: ^^ifaddrs) -> linux.Errno ---
  freeifaddrs :: proc "c" (ifa: ^ifaddrs) ---
}


SIOCSIFFLAGS :: bit_set[SIOCSIFFLAG;c.uint]
SIOCSIFFLAG :: enum {
  IFF_UP, // Interface is running.
  IFF_BROADCAST, // Valid broadcast address set.
  IFF_DEBUG, // Internal debugging flag.
  IFF_LOOPBACK, // Interface is a loopback interface.
  IFF_POINTOPOINT, // Interface is a point-to-point link.
  IFF_RUNNING, // Resources allocated.
  IFF_NOARP, // No arp protocol, L2 destination address not set.
  IFF_PROMISC, // Interface is in promiscuous mode.
  IFF_NOTRAILERS, // Avoid use of trailers.
  IFF_ALLMULTI, // Receive all multicast packets.
  IFF_MASTER, // Master of a load balancing bundle.
  IFF_SLAVE, // Slave of a load balancing bundle.
  IFF_MULTICAST, // Supports multicast
  IFF_PORTSEL, // Is able to select media type via ifmap.
  IFF_AUTOMEDIA, // Auto media selection active.
  IFF_DYNAMIC, // The addresses are lost when the interface goes down.
  IFF_LOWER_UP, // Driver signals L1 up (since Linux 2.6.17)
  IFF_DORMANT, // Driver signals dormant (since Linux 2.6.17)
  IFF_ECHO, // Echo sent packets (since Linux 2.6.25)
}

static_slice :: proc(arr: ^[$N]$T, $from: uint, $to: uint) -> [to - from]T {
  return (transmute(^[to - from]T)raw_data(arr[from:to]))^
}
