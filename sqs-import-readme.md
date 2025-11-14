# AWS SQS Terraform Import Script

A comprehensive bash script that automatically imports existing AWS SQS queues into Terraform, creating module configurations and maintaining infrastructure as code.

## 📋 Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Usage](#usage)
- [How It Works](#how-it-works)
- [Script Workflow](#script-workflow)
- [Generated Files](#generated-files)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)

## 🔍 Overview

This script automates the process of importing AWS SQS queues into Terraform by:
- Discovering all SQS queues in a specified AWS region
- Creating a reusable Terraform module for SQS queues
- Generating module calls with actual queue configurations
- Importing queues into Terraform state
- Creating output definitions for all imported queues

## ✨ Features

- **Zero Manual Configuration**: Automatically fetches all queue attributes from AWS
- **Module-Based Architecture**: Creates a reusable SQS module structure
- **Tag Preservation**: Imports all existing queue tags
- **FIFO Queue Support**: Correctly handles both standard and FIFO queues
- **Idempotent Operations**: Can be run multiple times safely (replaces old imports)
- **No External Dependencies**: Works with just AWS CLI and Terraform (no jq required)

## 📦 Prerequisites

Before running this script, ensure you have:

1. **AWS CLI** installed and configured
   ```bash
   aws --version
   ```

2. **Terraform** installed
   ```bash
   terraform --version
   ```

3. **AWS Credentials** configured with permissions to:
   - List SQS queues
   - Get queue attributes
   - List queue tags

4. **Existing Terraform Project** with a `main.tf` file

## 🚀 Usage

### Basic Usage

```bash
./sqs-queues-import.sh
```

This will import all SQS queues from the `us-east-1` region (default).

### Specify AWS Region

```bash
./sqs-queues-import.sh us-west-2
```

### Make Script Executable

```bash
chmod +x sqs-queues-import.sh
./sqs-queues-import.sh
```

## 🔧 How It Works

### 1. Module Creation

The script creates a reusable Terraform module at `modules/sqs/` with three files:

#### `main.tf`
```hcl
resource "aws_sqs_queue" "main" {
  name                        = var.queue_name
  fifo_queue                  = var.fifo_queue
  visibility_timeout_seconds  = var.visibility_timeout_seconds
  message_retention_seconds   = var.message_retention_seconds
  max_message_size            = var.max_message_size
  delay_seconds               = var.delay_seconds
  receive_wait_time_seconds   = var.receive_wait_time_seconds
  tags = var.tags
}
```

#### `variables.tf`
Defines all configurable parameters with sensible defaults.

#### `outputs.tf`
Exposes queue URL and ARN for reference.

### 2. Queue Discovery

```bash
aws sqs list-queues --region us-east-1 --output json
```

Discovers all queues in the specified region.

### 3. Attribute Extraction

For each queue, the script fetches:
- Visibility timeout
- Message retention period
- Maximum message size
- Delay seconds
- Receive wait time
- FIFO queue status
- All tags

### 4. Module Call Generation

Creates module blocks in `main.tf`:

```hcl
module "sqs_dev_global_pinpoint_notification_dlq" {
  source = "./modules/sqs"
  
  queue_name                    = "dev_global_pinpoint_notification_dlq"
  fifo_queue                    = false
  visibility_timeout_seconds    = 300
  message_retention_seconds     = 604800
  max_message_size              = 1048576
  delay_seconds                 = 10
  receive_wait_time_seconds     = 0
  
  tags = {
    Project = "Omron-Foresight-Api"
  }
}
```

### 5. Output Generation

Creates outputs in `output.tf`:

```hcl
output "sqs_dev_global_pinpoint_notification_dlq_url" {
  description = "URL of the dev_global_pinpoint_notification_dlq SQS queue"
  value       = module.sqs_dev_global_pinpoint_notification_dlq.queue_url
}

output "sqs_dev_global_pinpoint_notification_dlq_arn" {
  description = "ARN of the dev_global_pinpoint_notification_dlq SQS queue"
  value       = module.sqs_dev_global_pinpoint_notification_dlq.queue_arn
}
```

### 6. Terraform Import

Imports each queue into Terraform state:

```bash
terraform import module.sqs_dev_global_pinpoint_notification_dlq.aws_sqs_queue.main \
  https://sqs.us-east-1.amazonaws.com/689344065739/dev_global_pinpoint_notification_dlq
```

## 📊 Script Workflow

```
┌─────────────────────────────────────┐
│  Start Script                       │
│  (with optional region parameter)   │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Create/Recreate modules/sqs/       │
│  - main.tf                          │
│  - variables.tf                     │
│  - outputs.tf                       │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Clean up old imports               │
│  - Remove old module calls          │
│  - Remove old outputs               │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Discover SQS Queues                │
│  aws sqs list-queues                │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  For each queue:                    │
│  1. Get queue attributes            │
│  2. Get queue tags                  │
│  3. Generate module call            │
│  4. Generate outputs                │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Run terraform init                 │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Import each queue to state         │
│  terraform import                   │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  Complete!                          │
│  Run terraform plan to verify       │
└─────────────────────────────────────┘
```

## 📁 Generated Files

After running the script, your project structure will look like:

```
.
├── main.tf                           # Updated with module calls
├── output.tf                         # Updated with queue outputs
├── terraform.tfstate                 # Updated with imported queues
├── sqs-queues-import.sh             # This script
└── modules/
    └── sqs/
        ├── main.tf                   # SQS queue resource
        ├── variables.tf              # Module variables
        └── outputs.tf                # Module outputs
```

## 📸 Examples

### Running the Script

![Script Execution](https://github.com/user/repo/images/script-execution.png)
*The script discovers and processes 8 SQS queues*

### Terraform Init

![Terraform Init](https://github.com/user/repo/images/terraform-init.png)
*Initializing Terraform with the new module*

### Import Success

![Import Success](https://github.com/user/repo/images/import-success.png)
*Successfully importing queues into Terraform state*

### Terraform Plan

![Terraform Plan](https://github.com/user/repo/images/terraform-plan.png)
*Verification showing no changes needed*

### State List

![State List](https://github.com/user/repo/images/state-list.png)
*All 8 queues successfully imported*

### Generated Configuration

![Generated Config](https://github.com/user/repo/images/generated-config.png)
*Module call with actual queue configuration*

## 🐛 Troubleshooting

### No Queues Found

**Error**: `No queues found in region us-east-1`

**Solution**: 
- Verify your AWS credentials are configured correctly
- Check you have permissions to list SQS queues
- Ensure queues exist in the specified region

### Import Failures

**Error**: `Import failed with exit code: 1`

**Solution**:
- Verify the queue still exists in AWS
- Check Terraform has proper AWS provider configuration
- Ensure the queue URL format is correct

### Module Already Exists

The script automatically overwrites the `modules/sqs` directory if it exists, so this shouldn't be an issue.

### Duplicate Module Calls

The script removes all old module calls before adding new ones by looking for the comment marker `# Imported SQS Queues -`.

## 📝 Key Features Explained

### Resource Naming Convention

Queue names are transformed to valid Terraform resource names:
- Hyphens → underscores
- Dots → underscores
- Uppercase → lowercase

Example: `dev-Global-Pinpoint.DLQ` → `dev_global_pinpoint_dlq`

### FIFO Queue Detection

The script properly detects FIFO queues by checking the `FifoQueue` attribute:

```bash
FIFO_ATTR=$(echo "$ATTRS" | grep -o '"FifoQueue": *"[a-zA-Z]*"' | grep -o '[a-zA-Z]*' | tail -1)
if [ "$FIFO_ATTR" == "true" ]; then
  FIFO_FLAG=true
else
  FIFO_FLAG=false
fi
```

### Tag Parsing

Tags are parsed from JSON and converted to Terraform map format without requiring `jq`:

```bash
TAG_PAIRS=$(echo "$TAG_OUTPUT" | grep -o '"[^"]*": *"[^"]*"' | grep -v '"Tags"')
```

### Idempotent Design

- Old imports are removed before new ones are added
- Terraform state is properly managed
- Can be safely run multiple times

## 🔐 Security Considerations

- Never commit AWS credentials to the repository
- Use IAM roles with minimal required permissions
- Review generated configurations before applying
- Consider using Terraform workspaces for different environments

## 📄 License

This script is provided as-is for automating SQS queue imports into Terraform.

## 🤝 Contributing

Contributions are welcome! Please ensure:
- The script remains dependency-free (no jq requirement)
- All AWS regions are supported
- Error handling is robust

## 📞 Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review Terraform and AWS CLI documentation
3. Verify AWS credentials and permissions

---

**Note**: Always run `terraform plan` after importing to verify the configuration matches your infrastructure before applying any changes.