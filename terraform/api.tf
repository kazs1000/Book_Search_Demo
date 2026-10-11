data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "book-search-dev-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

}

data "aws_iam_policy_document" "lambda_logs" {
  statement {
    sid    = "AllowLambdaWriteLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.lambda.arn}:*"
    ]
  }
}

resource "aws_iam_role_policy" "lambda_logs" {
  name   = "book-search-dev-lambda-logs"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_logs.json
}

resource "aws_lambda_function" "api" {
  function_name = "book-search-dev-api"
  role          = aws_iam_role.lambda.arn

  filename         = "${path.module}/../dist/lambda.zip"
  source_code_hash = filebase64sha256("${path.module}/../dist/lambda.zip")

  handler = "app.handler"

  runtime     = "python3.12"
  memory_size = 128
  timeout     = 10

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda_logs
  ]

}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/book-search-dev-api"
  retention_in_days = 14

}

resource "aws_apigatewayv2_api" "api" {
  name          = "book-search-dev-http-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "api" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "health" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /api/health"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_apigatewayv2_route" "books" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /api/books"
  target    = "integrations/${aws_apigatewayv2_integration.api.id}"
}

resource "aws_lambda_permission" "api_health" {
  statement_id  = "AllowAPIGatewayInvokeGetHealth"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/$default/GET/api/health"
}

resource "aws_lambda_permission" "api_books" {
  statement_id  = "AllowAPIGatewayInvokeGetBooks"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/$default/GET/api/books"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true

  depends_on = [
    aws_apigatewayv2_route.health,
    aws_apigatewayv2_route.books,
    aws_lambda_permission.api_health,
    aws_lambda_permission.api_books
  ]

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_access.arn

    format = jsonencode({
      requestId      = "$context.requestId"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
    })
  }

  default_route_settings {
    throttling_burst_limit = local.api_throttling_burst_limit
    throttling_rate_limit  = local.api_throttling_rate_limit
  }
}

resource "aws_cloudwatch_log_group" "api_access" {
  name              = "/aws/apigateway/book-search-dev-http-api"
  retention_in_days = 14
}
