/**
 * VPC flow logs for both VPCs, delivered to CloudWatch Logs.
 *
 * Useful during an event for diagnosing "team X says their traffic isn't
 * getting through" and after an event for retrospective analysis.
 */

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/ranger-flow-logs"
  retention_in_days = 14

  tags = {
    Name = "ranger_flow_logs"
  }
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "ranger_flow_logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "ranger_flow_logs"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

resource "aws_flow_log" "main" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.ranger_main.id

  tags = {
    Name = "ranger_main_flow_log"
  }
}

resource "aws_flow_log" "teams" {
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.flow_logs.arn
  traffic_type    = "ALL"
  vpc_id          = aws_vpc.ranger_teams.id

  tags = {
    Name = "ranger_teams_flow_log"
  }
}
