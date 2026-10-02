# Reserved public IPv4 address of the application's external Application Load Balancer.
# The Ingress claims it by name (kubernetes.io/ingress.global-static-ip-name), so the address
# survives Ingress re-creation and stays stable for DNS, client allowlists and log queries.
resource "google_compute_global_address" "app_ingress" {
  name         = "ehc-app-ip"
  description  = "Public address of the tasky external Application Load Balancer"
  address_type = "EXTERNAL"
  ip_version   = "IPV4"
}
