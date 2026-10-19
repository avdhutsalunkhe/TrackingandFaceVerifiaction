import socket
import ipaddress
import urllib.request
import threading
from typing import List, Dict, Any
from fastapi import Request

_cached_public_ip: str = "115.244.240.22"
_last_public_ip_check: float = 0.0

def get_public_ip() -> str:
    """
    Retrieves or returns the cached public IP of this server.
    """
    global _cached_public_ip, _last_public_ip_check
    import time
    now = time.time()
    if _cached_public_ip and (now - _last_public_ip_check < 300):
        return _cached_public_ip

    def _fetch():
        global _cached_public_ip, _last_public_ip_check
        for provider in ("https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com"):
            try:
                req = urllib.request.Request(provider, headers={"User-Agent": "curl/7.68.0"})
                with urllib.request.urlopen(req, timeout=3) as resp:
                    ip = resp.read().decode("utf-8").strip()
                    if ip:
                        _cached_public_ip = ip
                        _last_public_ip_check = time.time()
                        return
            except Exception:
                continue

    # Non-blocking fetch if we already have a cached IP
    if _cached_public_ip:
        threading.Thread(target=_fetch, daemon=True).start()
    else:
        _fetch()

    return _cached_public_ip or "115.244.240.22"

def get_local_lan_ip() -> str:
    """
    Detects the primary LAN IPv4 address of the current host machine.
    """
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # 8.8.8.8 is used to determine the default interface route, no packet is actually sent
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        try:
            return socket.gethostbyname(socket.gethostname())
        except Exception:
            return "192.168.1.91"

def get_all_network_ips() -> List[str]:
    """
    Returns a list of all IP addresses bound to network interfaces on this host.
    """
    ips = set()
    try:
        lan_ip = get_local_lan_ip()
        if lan_ip:
            ips.add(lan_ip)
        
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None):
            ip = info[4][0]
            if ":" not in ip and not ip.startswith("127.") and not ip.startswith("169.254."):
                ips.add(ip)
    except Exception:
        pass
    
    if not ips:
        ips.add("192.168.1.91")
    
    return sorted(list(ips))

def is_lan_ip(ip: str) -> bool:
    """
    Checks if a given IP address belongs to a private/LAN subnet or loopback.
    """
    if not ip or ip in ("localhost", "127.0.0.1", "::1"):
        return True
    try:
        ip_obj = ipaddress.ip_address(ip)
        return ip_obj.is_private or ip_obj.is_loopback or ip_obj.is_link_local
    except ValueError:
        return False

def get_client_ip(request: Request) -> str:
    """
    Extracts the client IP from FastAPI request headers, prioritizing proxy headers.
    """
    forwarded_for = request.headers.get("X-Forwarded-For")
    if forwarded_for:
        # First IP in X-Forwarded-For chain is client IP
        return forwarded_for.split(",")[0].strip()
    
    real_ip = request.headers.get("X-Real-IP")
    if real_ip:
        return real_ip.strip()
    
    if request.client and request.client.host:
        return request.client.host
    
    return "127.0.0.1"

def get_server_network_summary(port: int = 8084) -> Dict[str, Any]:
    """
    Generates network access information for local, LAN, and public access.
    """
    lan_ip = get_local_lan_ip()
    public_ip = get_public_ip()
    all_ips = get_all_network_ips()
    
    lan_urls = [f"http://{ip}:{port}" for ip in all_ips]
    if f"http://127.0.0.1:{port}" not in lan_urls:
        lan_urls.insert(0, f"http://127.0.0.1:{port}")

    public_url = f"http://{public_ip}:{port}" if public_ip else None

    return {
        "port": port,
        "primary_lan_ip": lan_ip,
        "primary_lan_url": f"http://{lan_ip}:{port}",
        "public_ip": public_ip,
        "public_url": public_url,
        "all_lan_urls": lan_urls,
        "docs_url": f"http://{lan_ip}:{port}/api/docs",
        "public_docs_url": f"http://{public_ip}:{port}/api/docs" if public_ip else None,
        "swagger_url": f"http://{lan_ip}:{port}/api/docs",
        "redoc_url": f"http://{lan_ip}:{port}/api/redoc",
        "health_url": f"http://{lan_ip}:{port}/api/health"
    }
