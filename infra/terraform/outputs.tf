output "instance_id" {
  description = "For SSM: aws ssm start-session --target <instance_id>"
  value       = aws_instance.app.id
}

output "public_ip" {
  description = "The Elastic IP of the app."
  value       = aws_eip.app.public_ip
}

output "backup_bucket" {
  description = "The S3 bucket of the SQLite snapshots."
  value       = aws_s3_bucket.backups.bucket
}
