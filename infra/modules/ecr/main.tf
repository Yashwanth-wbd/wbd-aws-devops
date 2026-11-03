locals {
  tags = merge(var.tags, { Component = "ecr" })
}

resource "aws_ecr_repository" "this" {
  for_each = toset(var.repositories)

  name                 = each.key
  image_tag_mutability = "IMMUTABLE"
  force_delete         = false

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = var.kms_key_arn
  }

  # Ignored when enhanced scanning is on (the registry rule below applies instead).
  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.tags, { Name = each.key })
}

# One scanning configuration per registry (account + region).
resource "aws_ecr_registry_scanning_configuration" "this" {
  scan_type = var.enhanced_scanning ? "ENHANCED" : "BASIC"

  rule {
    scan_frequency = var.enhanced_scanning ? "CONTINUOUS_SCAN" : "SCAN_ON_PUSH"

    repository_filter {
      filter      = "mmm/*"
      filter_type = "WILDCARD"
    }
  }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = aws_ecr_repository.this

  repository = each.value.name
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Delete untagged images"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = var.untagged_expiry_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the newest release images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["v"]
          countType     = "imageCountMoreThan"
          countNumber   = var.keep_release_images
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "Keep the newest sha- build images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = var.keep_sha_images
        }
        action = { type = "expire" }
      },
    ]
  })
}
