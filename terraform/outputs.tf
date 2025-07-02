output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "data_bucket_name" {
  description = "Name of the S3 bucket for CSV data and results"
  value       = aws_s3_bucket.data.id
}

output "data_bucket_arn" {
  description = "ARN of the S3 bucket for CSV data and results"
  value       = aws_s3_bucket.data.arn
}

output "rds_endpoint" {
  description = "RDS PostgreSQL Endpoint"
  value       = aws_db_instance.main.address
}

output "rds_port" {
  description = "RDS PostgreSQL Port"
  value       = aws_db_instance.main.port
}

output "table_creator_function_name" {
  description = "Table Creator Lambda Function Name"
  value       = aws_lambda_function.table_creator.function_name
}

output "csv_processor_function_name" {
  description = "CSV Processor Lambda Function Name"
  value       = aws_lambda_function.csv_processor.function_name
}

output "query_executor_function_name" {
  description = "Query Executor Lambda Function Name"
  value       = aws_lambda_function.query_executor.function_name
}

output "lambda_layer_arn" {
  description = "psycopg2 Lambda Layer ARN"
  value       = aws_lambda_layer_version.psycopg2.arn
}

output "deployment_instructions" {
  description = "Next steps after deployment"
  value = <<-EOT
    === デプロイ完了！===
    
    1. テスト用CSVファイルをアップロード:
       aws s3 cp your-file.csv s3://${aws_s3_bucket.data.id}/csv/
    
    2. Lambda関数ログの確認:
       aws logs tail /aws/lambda/${aws_lambda_function.csv_processor.function_name} --follow
    
    3. RDS接続確認 (VPC内のEC2から):
       psql -h ${aws_db_instance.main.address} -U ${var.db_master_username} -d ${aws_db_instance.main.db_name}
  EOT
}