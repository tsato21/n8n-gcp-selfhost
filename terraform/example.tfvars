project_id       = "your-gcp-project-id"
region           = "us-west1"      # Free-tier eligible region (also us-central1, us-east1)
zone             = "us-west1-b"    # Zone within the region; choose any available in us-west1 (e.g., a/b/c)

# Prefix applied to resource names (VM, SA, firewall, secret, etc.)
# Include environment name to avoid collisions, e.g., "prod-", "stg-", "dev-"
resource_prefix  = "xxx-"

# Base names (prefix is added automatically)
secret_name      = "env"

repo_url         = "https://github.com/tsato21/n8n-gcp-selfhost"
github_owner     = "tsato21"
github_repo      = "n8n-gcp-selfhost"
tag_regex        = "^v\\d+\\.\\d+\\.\\d+$" # semantic version tags like v1.2.3

# Cloud Build SSH key here
cloudbuild_ssh_key_pub = "cloudbuild-ssh-key.pub"
cloudbuild_ssh_key_secret_id = "cloudbuild-ssh-key"

# Secret Manager > env
dotenv_content = <<-EOT
NODE_ENV=
DOMAIN_NAME=example.com
SUBDOMAIN=
GENERIC_TIMEZONE=Asia/Tokyo
SSL_EMAIL=you@example.com
BASIC_AUTH_USERS=username:$2y$05$replace_with_bcrypt_hash

 # --- SMTP (Password reset / invites / notifications) ---
 # Enable email sending in n8n UI (recommended for account recovery when 2FA is used)
 N8N_EMAIL_MODE=smtp
 N8N_SMTP_HOST=smtp.example.com
 N8N_SMTP_PORT=587
 N8N_SMTP_USER=
 N8N_SMTP_PASS=
 # If your provider requires implicit SSL (465), set to "true" and N8N_SMTP_PORT=465
 N8N_SMTP_SSL=false
 # Sender address shown in emails
 N8N_SMTP_SENDER="n8n <no-reply@example.com>"
EOT
