locals {
  binary_name  = lower(var.function_name)
  binary_path  = "${path.module}/tf_generated/${local.binary_name}"
  node_path    = var.src_path
  archive_path = "${path.module}/tf_generated/${var.function_name}.zip"
}

resource "null_resource" "function_binary" {
  count = var.runtime == "go1.x" ? 1 : 0
  triggers = {
    source_hash = join("", [for f in fileset(var.src_path, "*.go") : filesha256("${var.src_path}/${f}")])
    binary_hash = fileexists(local.binary_path) ? filesha256(local.binary_path) : uuid()
  }

  provisioner "local-exec" {
    command = "GOOS=linux GOARCH=amd64 CGO_ENABLED=0 GOFLAGS=-trimpath go build -mod=readonly -ldflags='-s -w' -o ${local.binary_path} ${var.src_path}"
  }
}

resource "null_resource" "js_function_files" {
  count = var.runtime == "go1.x" ? 0 : 1
  triggers = {
    source_hash = join("", [for f in fileset(var.src_path, "*.js") : filesha256("${var.src_path}/${f}")])
  }
}

data "archive_file" "function_archive_go" {
  count      = var.runtime == "go1.x" ? 1 : 0
  depends_on = [null_resource.function_binary]

  type        = "zip"
  source_file = local.binary_path
  output_path = local.archive_path
}

data "archive_file" "function_archive_node" {
  count      = var.runtime == "go1.x" ? 0 : 1
  depends_on = [null_resource.js_function_files]

  type        = "zip"
  source_dir  = var.src_path
  output_path = local.archive_path
}

resource "aws_lambda_function" "function" {
  function_name = var.function_name
  description   = var.function_description
  role          = data.aws_iam_role.role.arn
  handler       = local.binary_name
  memory_size   = var.memory_size

  filename         = local.archive_path
  source_code_hash = var.runtime == "go1.x" ? data.archive_file.function_archive_go[0].output_base64sha256 : data.archive_file.function_archive_node[0].output_base64sha256

  runtime = var.runtime
  timeout = var.timeout_seconds
  tags    = var.tags

  dynamic "environment" {
    for_each = length(var.environment) == 0 ? [] : [var.environment]
    content {
      variables = environment.value
    }
  }
}

data "aws_iam_role" "role" {
  name = var.role_name
}

resource "aws_cloudwatch_log_group" "log_group" {
  name              = "/aws/lambda/${aws_lambda_function.function.function_name}"
  retention_in_days = var.log_retention_days
}
