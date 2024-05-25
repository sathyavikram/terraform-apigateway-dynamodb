resource "aws_dynamodb_table" "books-dynamodb-table" {
  name      = "books"
  hash_key  = "userId"
  range_key = "addedOn"

  attribute {
    name = "userId"
    type = "S"
  }

  attribute {
    name = "addedOn"
    type = "S"
  }
  billing_mode = "PAY_PER_REQUEST"
}
