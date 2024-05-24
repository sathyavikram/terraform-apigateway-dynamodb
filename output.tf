output "web_urls_endpoint" {
  value       = aws_api_gateway_stage.BooksApi.invoke_url
  description = "Books API endpoint"
}