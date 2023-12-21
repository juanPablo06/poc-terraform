terraform {
  backend "s3" {
    bucket = "terraform-backend-ue1"
    key    = "digger-poc"
    region = "us-east-1"
  }
}
