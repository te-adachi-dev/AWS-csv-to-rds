# Lambda実行用IAMロール
resource "aws_iam_role" "lambda_execution" {
  name_prefix = "${var.project_name}-lambda-exec-"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name = "${var.project_name}-lambda-execution-role"
  }
}

# Lambda実行ロールにポリシーアタッチ
resource "aws_iam_role_policy_attachment" "lambda_vpc_access" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.lambda_execution.name
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"  
  role       = aws_iam_role.lambda_execution.name
}

# S3アクセス用インラインポリシー
resource "aws_iam_role_policy" "lambda_s3_access" {
  name = "${var.project_name}-lambda-s3-access"
  role = aws_iam_role.lambda_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          "arn:aws:s3:::${var.source_bucket}/*",
          "arn:aws:s3:::${var.source_bucket}",
          aws_s3_bucket.data.arn,
          "${aws_s3_bucket.data.arn}/*"
        ]
      }
    ]
  })
}

# カスタムリソース用IAMロール
resource "aws_iam_role" "custom_resource_lambda" {
  name_prefix = "etl-custom-res-"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
  
  tags = {
    Name = "${var.project_name}-custom-resource-execution-role"
  }
}

# カスタムリソース用ポリシーアタッチ
resource "aws_iam_role_policy_attachment" "custom_resource_vpc_access" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
  role       = aws_iam_role.custom_resource_lambda.name
}

resource "aws_iam_role_policy_attachment" "custom_resource_basic_execution" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.custom_resource_lambda.name
}

# カスタムリソース用追加ポリシー
resource "aws_iam_role_policy" "custom_resource_policy" {
  name = "${var.project_name}-custom-resource-policy"
  role = aws_iam_role.custom_resource_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketNotification",
          "s3:PutBucketNotification"
        ]
        Resource = aws_s3_bucket.data.arn
      }
    ]
  })
}

# データソース
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}