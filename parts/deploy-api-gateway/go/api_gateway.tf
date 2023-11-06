// create an API gateway for HTTP API
resource "aws_apigatewayv2_api" "simple_api" {
  name          = "simple-api"
  protocol_type = "HTTP"
  description   = "Serverless API gateway for HTTP API and AWS Lambda function"

  cors_configuration {
    allow_headers = ["*"]
    allow_methods = [
      "GET",
      "HEAD",
      "OPTIONS",
      "POST",
    ]
    allow_origins = [
      "*" // NOTE: here we should provide a particular domain, but for the sake of simplicity we will use "*"
    ]
    expose_headers = []
    max_age        = 0
  }
}

// create a stage for API GW
resource "aws_apigatewayv2_stage" "simple_api" {
  api_id = aws_apigatewayv2_api.simple_api.id

  name        = "golang"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
  depends_on = [aws_cloudwatch_log_group.api_gw]
}

// create logs for API GW
resource "aws_cloudwatch_log_group" "api_gw" {
  name = "/aws/api_gw/${aws_apigatewayv2_api.simple_api.name}"

  retention_in_days = 7
}

// create lambda function to invoke lambda when specific HTTP request is made via API GW
resource "aws_apigatewayv2_integration" "hello_world_lambda" {
  api_id = aws_apigatewayv2_api.simple_api.id

  integration_uri  = aws_lambda_function.hello_world.arn
  integration_type = "AWS_PROXY"
}

// specify route that will be used to invoke lambda function
resource "aws_apigatewayv2_route" "hello_world_lambda" {
  api_id    = aws_apigatewayv2_api.simple_api.id
  route_key = "GET /api/v1/hello"
  target    = "integrations/${aws_apigatewayv2_integration.hello_world_lambda.id}"
}

// provide permission for API GW to invoke lambda function
resource "aws_lambda_permission" "hello_world_lambda" {
  statement_id  = "tutorial-api-gateway-hello"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello_world.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.simple_api.execution_arn}/*/*"
}
