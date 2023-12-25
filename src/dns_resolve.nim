import nativesockets


proc resolveIPv4*(address : string):string=
    let host =  getHostByName(address)
    return host.addrList[0]