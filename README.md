# terraform-workshop
INFC Terraform Workshop 3

*Why do we need Terraform Cloud (or another backend) when we use CI/CD?*

Terraform is a stateful service, it saves the configuration state into a `.tfstate` file. This happens so that it knows what to destroy if we want to revert our changes or what to update if we apply new changes. Git repos are meant for pushes from developers and it would be very messy if we would somehow push those Terraform state files into the repo, if it would even work at all.