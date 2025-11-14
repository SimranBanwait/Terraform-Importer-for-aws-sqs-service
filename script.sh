#!/bin/bash

################################################################################
# Simple SQS Import Script
# Usage: ./import_sqs.sh [aws-region]
################################################################################

REGION=${1:-us-east-1}
MODULE_NAME="sqs"

# Remove existing module folder if it exists and recreate
if [ -d "modules/${MODULE_NAME}" ]; then
    echo "Module folder modules/${MODULE_NAME} already exists. Overwriting..."
    rm -rf "modules/${MODULE_NAME}"
fi

echo "Using module folder: ${MODULE_NAME}"

# Create module directory
mkdir -p "modules/${MODULE_NAME}"

# Create module main.tf
cat > "modules/${MODULE_NAME}/main.tf" << 'EOF'
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
EOF

# Create module variables.tf
cat > "modules/${MODULE_NAME}/variables.tf" << 'EOF'
variable "queue_name" {
  type = string
}

variable "fifo_queue" {
  type    = bool
  default = false
}

variable "visibility_timeout_seconds" {
  type    = number
  default = 30
}

variable "message_retention_seconds" {
  type    = number
  default = 345600
}

variable "max_message_size" {
  type    = number
  default = 262144
}

variable "delay_seconds" {
  type    = number
  default = 0
}

variable "receive_wait_time_seconds" {
  type    = number
  default = 0
}

variable "tags" {
  type    = map(string)
  default = {}
}
EOF

# Create module outputs.tf
cat > "modules/${MODULE_NAME}/outputs.tf" << 'EOF'
output "queue_url" {
  value = aws_sqs_queue.main.id
}

output "queue_arn" {
  value = aws_sqs_queue.main.arn
}
EOF

echo "Module created at modules/${MODULE_NAME}"

# Backup main.tf
# cp main.tf "main.tf.backup.$(date +%Y%m%d_%H%M%S)"

# Remove ALL previously imported SQS module calls from main.tf
if grep -q "# Imported SQS Queues -" main.tf; then
    echo "Removing old SQS module calls from main.tf..."
    # Delete everything from "# Imported SQS Queues" marker to end of file
    sed '/# Imported SQS Queues -/,$d' main.tf > main.tf.tmp && mv main.tf.tmp main.tf
fi

# Get all queue URLs using JSON output
echo "Fetching SQS queues from region: ${REGION}..."
QUEUE_LIST=$(aws sqs list-queues --region ${REGION} --output json 2>/dev/null)

# Parse queue URLs from JSON (without jq)
QUEUE_URLS=$(echo "$QUEUE_LIST" | grep -o '"https://[^"]*"' | tr -d '"')

if [ -z "$QUEUE_URLS" ]; then
    echo "No queues found in region ${REGION}"
    echo "Debug: AWS CLI output was:"
    echo "$QUEUE_LIST"
    exit 1
fi

# Count queues
QUEUE_COUNT=$(echo "$QUEUE_URLS" | wc -l)
echo "Found ${QUEUE_COUNT} queue(s)"

# Add fresh module calls for ALL queues
echo "" >> main.tf
echo "# Imported SQS Queues - $(date)" >> main.tf

# Process each queue and add to main.tf
while IFS= read -r QUEUE_URL; do
    if [ -z "$QUEUE_URL" ]; then
        continue
    fi
    
    # Get queue name from URL (last part after /)
    QUEUE_NAME=$(echo "$QUEUE_URL" | awk -F'/' '{print $NF}')
    RESOURCE_NAME=$(echo "$QUEUE_NAME" | tr '-' '_' | tr '.' '_' | tr '[:upper:]' '[:lower:]')
    
    echo "Processing: $QUEUE_NAME"
    
    # Get queue attributes
    ATTRS=$(aws sqs get-queue-attributes --queue-url "$QUEUE_URL" --attribute-names All --region ${REGION} --output json 2>/dev/null)
    
    # Parse attributes from JSON
    VIS_TIMEOUT=$(echo "$ATTRS" | grep -o '"VisibilityTimeout": *"[0-9]*"' | grep -o '[0-9]*' | head -1)
    MSG_RETENTION=$(echo "$ATTRS" | grep -o '"MessageRetentionPeriod": *"[0-9]*"' | grep -o '[0-9]*' | tail -1)
    MAX_SIZE=$(echo "$ATTRS" | grep -o '"MaximumMessageSize": *"[0-9]*"' | grep -o '[0-9]*' | tail -1)
    DELAY=$(echo "$ATTRS" | grep -o '"DelaySeconds": *"[0-9]*"' | grep -o '[0-9]*' | tail -1)
    WAIT_TIME=$(echo "$ATTRS" | grep -o '"ReceiveMessageWaitTimeSeconds": *"[0-9]*"' | grep -o '[0-9]*' | tail -1)

  # Determine if the queue is FIFO using attributes
  FIFO_ATTR=$(echo "$ATTRS" | grep -o '"FifoQueue": *"[a-zA-Z]*"' | grep -o '[a-zA-Z]*' | tail -1)
  if [ "$FIFO_ATTR" == "true" ]; then
    FIFO_FLAG=true
  else
    FIFO_FLAG=false
  fi

    # Get existing tags
    TAG_OUTPUT=$(aws sqs list-queue-tags --queue-url "$QUEUE_URL" --region ${REGION} --output json 2>/dev/null)
    
    # Parse tags into Terraform map format
    TAGS_BLOCK=""
    if echo "$TAG_OUTPUT" | grep -q '"Tags"'; then
        # Extract tag key-value pairs
        TAG_PAIRS=$(echo "$TAG_OUTPUT" | grep -o '"[^"]*": *"[^"]*"' | grep -v '"Tags"')
        
        if [ -n "$TAG_PAIRS" ]; then
            TAGS_BLOCK="  tags = {"
            while IFS= read -r TAG_PAIR; do
                if [ -n "$TAG_PAIR" ]; then
                    TAG_KEY=$(echo "$TAG_PAIR" | cut -d':' -f1 | tr -d '"' | sed 's/^ *//;s/ *$//')
                    TAG_VALUE=$(echo "$TAG_PAIR" | cut -d':' -f2- | tr -d '"' | sed 's/^ *//;s/ *$//')
                    TAGS_BLOCK="${TAGS_BLOCK}
    ${TAG_KEY} = \"${TAG_VALUE}\""
                fi
            done <<< "$TAG_PAIRS"
            TAGS_BLOCK="${TAGS_BLOCK}
  }"
        else
            TAGS_BLOCK="  tags = {}"
        fi
    else
        TAGS_BLOCK="  tags = {}"
    fi
    
    # Add module to main.tf
    cat >> main.tf << EOF

module "sqs_${RESOURCE_NAME}" {

  source = "./modules/${MODULE_NAME}"
  
  queue_name                    = "${QUEUE_NAME}"
  fifo_queue                     = ${FIFO_FLAG}
  visibility_timeout_seconds    = ${VIS_TIMEOUT:-30}
  message_retention_seconds     = ${MSG_RETENTION:-345600}
  max_message_size             = ${MAX_SIZE:-262144}
  delay_seconds                = ${DELAY:-0}
  receive_wait_time_seconds    = ${WAIT_TIME:-0}
  
${TAGS_BLOCK}
}
EOF

done <<< "$QUEUE_URLS"

echo ""
echo "Module calls added to main.tf (replaced old ones)"

# Generate outputs for each queue in output.tf (note: singular "output.tf")
echo ""
echo "Adding outputs to output.tf..."

# Backup output.tf if it exists
if [ -f "output.tf" ]; then
    # cp output.tf "output.tf.backup.$(date +%Y%m%d_%H%M%S)"
    
    # Remove only the SQS Queue Outputs section if it exists (keep everything else)
    if grep -q "# SQS Queue Outputs -" output.tf; then
        echo "Removing old SQS outputs from output.tf..."
        # This awk script removes only the SQS outputs section
        awk '
            BEGIN { in_sqs=0; buffer="" }
            /^# SQS Queue Outputs -/ { 
                in_sqs=1
                next 
            }
            in_sqs && /^output "sqs_/ {
                # Skip the entire output block
                brace_count=0
                while (getline) {
                    if ($0 ~ /{/) brace_count++
                    if ($0 ~ /}/) {
                        brace_count--
                        if (brace_count == 0) break
                    }
                }
                next
            }
            in_sqs && /^$/ {
                # Skip empty lines in SQS section
                next
            }
            in_sqs && /^#/ && !/^# SQS/ {
                # Found a new section, stop removing
                in_sqs=0
                print
                next
            }
            !in_sqs || (in_sqs && !/^output "sqs_/ && !/^$/) {
                if (!in_sqs) print
            }
        ' output.tf > output.tf.tmp && mv output.tf.tmp output.tf
    fi
else
    # Create output.tf if it doesn't exist
    touch output.tf
fi

# Add outputs for each queue at the end of the file
echo "" >> output.tf
echo "# SQS Queue Outputs - $(date)" >> output.tf

while IFS= read -r QUEUE_URL; do
    if [ -z "$QUEUE_URL" ]; then
        continue
    fi
    
    QUEUE_NAME=$(echo "$QUEUE_URL" | awk -F'/' '{print $NF}')
    RESOURCE_NAME=$(echo "$QUEUE_NAME" | tr '-' '_' | tr '.' '_' | tr '[:upper:]' '[:lower:]')
    
    cat >> output.tf << EOF

output "sqs_${RESOURCE_NAME}_url" {
  description = "URL of the ${QUEUE_NAME} SQS queue"
  value       = module.sqs_${RESOURCE_NAME}.queue_url
}

output "sqs_${RESOURCE_NAME}_arn" {
  description = "ARN of the ${QUEUE_NAME} SQS queue"
  value       = module.sqs_${RESOURCE_NAME}.queue_arn
}
EOF

done <<< "$QUEUE_URLS"

echo "Outputs added to output.tf"

# Init terraform
echo ""
echo "Running terraform init..."
terraform init

# Import each queue
echo ""
echo "Importing queues to state..."

while IFS= read -r QUEUE_URL; do
    if [ -z "$QUEUE_URL" ]; then
        continue
    fi
    
    QUEUE_NAME=$(echo "$QUEUE_URL" | awk -F'/' '{print $NF}')
    RESOURCE_NAME=$(echo "$QUEUE_NAME" | tr '-' '_' | tr '.' '_' | tr '[:upper:]' '[:lower:]')
    
    # Extract account ID from queue URL
    ACCOUNT_ID=$(echo "$QUEUE_URL" | awk -F'/' '{print $(NF-1)}')
    
    # Construct proper SQS URL format for import
    PROPER_QUEUE_URL="https://sqs.${REGION}.amazonaws.com/${ACCOUNT_ID}/${QUEUE_NAME}"
    
    echo "Importing: $QUEUE_NAME"
    echo "  Module: module.sqs_${RESOURCE_NAME}.aws_sqs_queue.main"
    echo "  URL: $PROPER_QUEUE_URL"
    
    terraform import -input=false "module.sqs_${RESOURCE_NAME}.aws_sqs_queue.main" "$PROPER_QUEUE_URL"
    
    IMPORT_STATUS=$?
    if [ $IMPORT_STATUS -eq 0 ]; then
        echo "  ✓ Import successful"
    else
        echo "  ✗ Import failed with exit code: $IMPORT_STATUS"
    fi
    echo ""
done <<< "$QUEUE_URLS"

echo ""
echo "Done! Run 'terraform plan' to verify."
