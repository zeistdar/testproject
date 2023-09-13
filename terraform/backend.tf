terraform {
  backend "s3" {
    bucket  = "my-terraform-state-bucket"
    key     = "prod/terraform.tfstate"
    region  = "us-west-1"
    encrypt = true
    dynamodb_table = "terraform-up-and-running-locks"
  }
}