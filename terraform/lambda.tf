# psycopg2 Layer
resource "aws_lambda_layer_version" "psycopg2" {
  layer_name = "${var.project_name}-psycopg2-layer"
  s3_bucket  = var.source_bucket
  s3_key     = var.psycopg2_layer_key

  compatible_runtimes = ["python3.11"]
  description         = "psycopg2 library for PostgreSQL connectivity"
}

# Table Creator Lambda Function
resource "aws_lambda_function" "table_creator" {
  function_name = "${var.project_name}-table-creator"
  runtime       = "python3.11"
  handler       = "table_creator.lambda_handler"
  role          = aws_iam_role.lambda_execution.arn
  timeout       = 900
  memory_size   = 1024

  s3_bucket = var.source_bucket
  s3_key    = var.table_creator_code_key

  layers = [aws_lambda_layer_version.psycopg2.arn]

  vpc_config {
    security_group_ids = [aws_security_group.lambda.id]
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  }

  environment {
    variables = {
      DB_HOST    = aws_db_instance.main.address
      DB_PORT    = aws_db_instance.main.port
      DB_NAME    = aws_db_instance.main.db_name
      DB_USER    = var.db_master_username
      DB_PASSWORD = var.db_master_password
      S3_BUCKET  = var.source_bucket
      SQL_PREFIX = var.init_sql_prefix
    }
  }

  tags = {
    Name = "${var.project_name}-table-creator"
  }

  depends_on = [aws_iam_role_policy.lambda_s3_access]
}

# CSV Processor Lambda Function
resource "aws_lambda_function" "csv_processor" {
  function_name = "${var.project_name}-csv-processor"
  runtime       = "python3.11"
  handler       = "csv_processor.lambda_handler"
  role          = aws_iam_role.lambda_execution.arn
  timeout       = 900
  memory_size   = 1024

  s3_bucket = var.source_bucket
  s3_key    = var.csv_processor_code_key

  layers = [aws_lambda_layer_version.psycopg2.arn]

  vpc_config {
    security_group_ids = [aws_security_group.lambda.id]
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  }

  environment {
    variables = {
      DB_HOST     = aws_db_instance.main.address
      DB_PORT     = aws_db_instance.main.port
      DB_NAME     = aws_db_instance.main.db_name
      DB_USER     = var.db_master_username
      DB_PASSWORD = var.db_master_password
      S3_BUCKET   = aws_s3_bucket.data.bucket
    }
  }

  tags = {
    Name = "${var.project_name}-csv-processor"
  }

  depends_on = [aws_iam_role_policy.lambda_s3_access]
}

# Query Executor Lambda Function
resource "aws_lambda_function" "query_executor" {
  function_name = "${var.project_name}-query-executor"
  runtime       = "python3.11"
  handler       = "query_executor.lambda_handler"
  role          = aws_iam_role.lambda_execution.arn
  timeout       = 900
  memory_size   = 1024

  s3_bucket = var.source_bucket
  s3_key    = var.query_executor_code_key

  layers = [aws_lambda_layer_version.psycopg2.arn]

  vpc_config {
    security_group_ids = [aws_security_group.lambda.id]
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  }

  environment {
    variables = {
      DB_HOST      = aws_db_instance.main.address
      DB_PORT      = aws_db_instance.main.port
      DB_NAME      = aws_db_instance.main.db_name
      DB_USER      = var.db_master_username
      DB_PASSWORD  = var.db_master_password
      S3_BUCKET    = aws_s3_bucket.data.bucket
      OUTPUT_PREFIX = "query-results/"
    }
  }

  tags = {
    Name = "${var.project_name}-query-executor"
  }

  depends_on = [aws_iam_role_policy.lambda_s3_access]
}

# Lambda Permission for S3
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.csv_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data.arn
}

# S3 Bucket Notification
resource "aws_s3_bucket_notification" "csv_upload" {
  bucket = aws_s3_bucket.data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.csv_processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "csv/"
    filter_suffix       = ".csv"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# Custom Resource Lambda for initialization
resource "aws_lambda_function" "custom_resource" {
  function_name = "${var.project_name}-custom-resource"
  runtime       = "python3.11"
  handler       = "index.lambda_handler"
  role          = aws_iam_role.custom_resource_lambda.arn
  timeout       = 900
  memory_size   = 512

  vpc_config {
    security_group_ids = [aws_security_group.lambda.id]
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  }

  environment {
    variables = {
      TABLE_CREATOR_FUNCTION_NAME = aws_lambda_function.table_creator.function_name
    }
  }

  filename         = data.archive_file.custom_resource.output_path
  source_code_hash = data.archive_file.custom_resource.output_base64sha256

  tags = {
    Name = "${var.project_name}-custom-resource"
  }

  depends_on = [
    aws_iam_role_policy.custom_resource_policy,
    aws_iam_role_policy_attachment.custom_resource_vpc_access,
    aws_iam_role_policy_attachment.custom_resource_basic_execution
  ]
}

# Create zip file for custom resource
data "archive_file" "custom_resource" {
  type        = "zip"
  output_path = "${path.module}/custom_resource.zip"

  source {
    content  = <<-EOF
import json
import boto3
import time

def lambda_handler(event, context):
    print(f"Event: {json.dumps(event)}")
    
    request_type = event.get('RequestType', 'Create')
    
    if request_type == 'Create':
        try:
            lambda_client = boto3.client('lambda')
            table_creator_function = event['ResourceProperties']['TableCreatorFunctionName']
            
            print(f"Invoking table creator function: {table_creator_function}")
            
            response = lambda_client.invoke(
                FunctionName=table_creator_function,
                InvocationType='RequestResponse',
                Payload=json.dumps({})
            )
            
            payload = response['Payload'].read()
            print(f"Table creator response: {payload}")
            
            return {
                'statusCode': 200,
                'body': json.dumps('Tables created successfully')
            }
        except Exception as e:
            print(f"Error: {str(e)}")
            return {
                'statusCode': 500,
                'body': json.dumps(f'Error: {str(e)}')
            }
    
    return {
        'statusCode': 200,
        'body': json.dumps('Operation completed')
    }
EOF
    filename = "index.py"
  }
}

# Invoke custom resource on creation
resource "null_resource" "init_tables" {
  provisioner "local-exec" {
    command = <<-EOT
      sleep 30
      aws lambda invoke \
        --function-name ${aws_lambda_function.custom_resource.function_name} \
        --payload '{"RequestType": "Create", "ResourceProperties": {"TableCreatorFunctionName": "${aws_lambda_function.table_creator.function_name}"}}' \
        /tmp/init_response.json || true
    EOT
  }

  depends_on = [
    aws_lambda_function.custom_resource,
    aws_lambda_function.table_creator,
    aws_db_instance.main
  ]
}