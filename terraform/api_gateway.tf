# API Gateway REST API
resource "aws_api_gateway_rest_api" "query_api" {
  name        = "${var.project_name}-query-api"
  description = "API for querying RDS from Excel"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
  
  # タグを空にしてdefault_tagsを無効化
  tags = {}
  
  lifecycle {
    ignore_changes = [tags_all]
  }
}

# リソース
resource "aws_api_gateway_resource" "query" {
  rest_api_id = aws_api_gateway_rest_api.query_api.id
  parent_id   = aws_api_gateway_rest_api.query_api.root_resource_id
  path_part   = "query"
}

# POSTメソッド
resource "aws_api_gateway_method" "query_post" {
  rest_api_id   = aws_api_gateway_rest_api.query_api.id
  resource_id   = aws_api_gateway_resource.query.id
  http_method   = "POST"
  authorization = "NONE"
  api_key_required = true
}

# Lambda統合
resource "aws_api_gateway_integration" "query_lambda" {
  rest_api_id = aws_api_gateway_rest_api.query_api.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_post.http_method

  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.api_query_executor.invoke_arn
}

# デプロイメント
resource "aws_api_gateway_deployment" "api" {
  rest_api_id = aws_api_gateway_rest_api.query_api.id

  depends_on = [
    aws_api_gateway_method.query_post,
    aws_api_gateway_integration.query_lambda
  ]

  lifecycle {
    create_before_destroy = true
  }
}

# ステージ（新しい方式）
resource "aws_api_gateway_stage" "prod" {
  deployment_id = aws_api_gateway_deployment.api.id
  rest_api_id   = aws_api_gateway_rest_api.query_api.id
  stage_name    = "prod"
  
  tags = {}
  
  lifecycle {
    ignore_changes = [tags_all]
  }
}

# APIキー
resource "aws_api_gateway_api_key" "excel_key" {
  name = "${var.project_name}-excel-key"
  
  # タグを空にしてdefault_tagsを無効化
  tags = {}
  
  lifecycle {
    ignore_changes = [tags_all]
  }
}

# 使用プラン
resource "aws_api_gateway_usage_plan" "plan" {
  name = "${var.project_name}-usage-plan"

  api_stages {
    api_id = aws_api_gateway_rest_api.query_api.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  quota_settings {
    limit  = 10000
    period = "DAY"
  }

  throttle_settings {
    rate_limit  = 100
    burst_limit = 200
  }
  
  # タグを空にしてdefault_tagsを無効化
  tags = {}
  
  lifecycle {
    ignore_changes = [tags_all]
  }
}

# 使用プランとAPIキーの関連付け
resource "aws_api_gateway_usage_plan_key" "plan_key" {
  key_id        = aws_api_gateway_api_key.excel_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.plan.id
}

# CORS設定
resource "aws_api_gateway_method" "query_options" {
  rest_api_id   = aws_api_gateway_rest_api.query_api.id
  resource_id   = aws_api_gateway_resource.query.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "query_options" {
  rest_api_id = aws_api_gateway_rest_api.query_api.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_options.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "query_options" {
  rest_api_id = aws_api_gateway_rest_api.query_api.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_options.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "query_options" {
  rest_api_id = aws_api_gateway_rest_api.query_api.id
  resource_id = aws_api_gateway_resource.query.id
  http_method = aws_api_gateway_method.query_options.http_method
  status_code = aws_api_gateway_method_response.query_options.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'GET,OPTIONS,POST,PUT'"
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
  }
}