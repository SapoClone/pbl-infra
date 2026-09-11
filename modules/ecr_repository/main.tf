resource "aws_ecr_repository" "this" {
  name = var.name

  # MUTABLE, not IMMUTABLE: the deploy workflows repeatedly overwrite a
  # ":buildcache" tag in this same repository (docker/build-push-action's
  # registry cache), which an immutable repo would reject.
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Keeps the repository from growing unbounded — untagged images (left
# behind by ":buildcache" pushes and failed builds) are the ones that pile
# up, since every real deploy tag is immutable and referenced by a task
# definition or Lambda version.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = { type = "expire" }
      }
    ]
  })
}
