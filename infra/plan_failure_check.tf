locals {
  plan_check_passes = false
}

resource "terraform_data" "plan_failure_check" {
  lifecycle {
    precondition {
      condition     = local.plan_check_passes
      error_message = "Plan stopped by a failing precondition."
    }
  }
}
