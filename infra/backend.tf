# State bucket is created outside Terraform (gcloud), before the first init
terraform {
  backend "gcs" {
    bucket = "clgcporg10-178-tfstate"
    prefix = "infra"
  }
}
