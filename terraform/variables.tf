variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "etl-csv-to-rds-postgresql"
}

variable "db_master_username" {
  description = "RDS Master Username"
  type        = string
  default     = "postgres"
}

variable "db_master_password" {
  description = "RDS Master Password (minimum 8 characters)"
  type        = string
  sensitive   = true
  default     = "TestPassword123!"
}

variable "source_bucket" {
  description = "S3 Bucket containing Lambda code and SQL files"
  type        = string
}

variable "csv_processor_code_key" {
  description = "S3 Key for CSV Processor Lambda code"
  type        = string
  default     = "lambda-code/csv_processor.zip"
}

variable "query_executor_code_key" {
  description = "S3 Key for Query Executor Lambda code"
  type        = string
  default     = "lambda-code/query_executor.zip"
}

variable "table_creator_code_key" {
  description = "S3 Key for Table Creator Lambda code"
  type        = string
  default     = "lambda-code/table_creator.zip"
}

variable "psycopg2_layer_key" {
  description = "S3 Key for psycopg2 Lambda Layer"
  type        = string
  default     = "layers/psycopg2-layer.zip"
}

variable "init_sql_prefix" {
  description = "S3 Prefix for initialization SQL files"
  type        = string
  default     = "init-sql/"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "poc"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "RDS allocated storage in GB"
  type        = number
  default     = 20
}

variable "api_query_executor_code_key" {
  description = "S3 Key for API Query Executor Lambda code"
  type        = string
  default     = "lambda-code/api_query_executor.zip"
}