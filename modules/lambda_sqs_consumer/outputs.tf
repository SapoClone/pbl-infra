output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "function_arn" {
  value = aws_lambda_function.this.arn
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}
