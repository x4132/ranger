/**
 * Shared IAM: an EC2 role with SSM managed-core access, plus bucket-specific
 * read/write permissions for VPN config distribution.
 *
 * - `ec2_ssm` base role: attached to admin, gameserver, checker.
 * - `vpn_server` role: base + s3:PutObject into the vpn_configs bucket.
 * - `vulnbox`  role: base + s3:GetObject for its own key prefix.
 */

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# Base role: SSM + CloudWatch agent. Attached directly to admin/gameserver/checker.
resource "aws_iam_role" "ec2_ssm" {
  name               = "ranger_ec2_ssm"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ec2_ssm_cwagent" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "ranger_ec2_ssm"
  role = aws_iam_role.ec2_ssm.name
}

# VPN server role: base + write .ovpn files into the vpn_configs bucket.
resource "aws_iam_role" "vpn_server" {
  name               = "ranger_vpn_server"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "vpn_server_ssm_core" {
  role       = aws_iam_role.vpn_server.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "vpn_server_s3" {
  statement {
    actions = [
      "s3:PutObject",
      "s3:PutObjectAcl",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.vpn_configs.arn,
      "${aws_s3_bucket.vpn_configs.arn}/*",
    ]
  }
}

# Gameserver role: base + read team_*.ovpn so the scoreboard can serve them as
# per-team downloads.
resource "aws_iam_role" "gameserver" {
  name               = "ranger_gameserver"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "gameserver_ssm_core" {
  role       = aws_iam_role.gameserver.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "gameserver_cwagent" {
  role       = aws_iam_role.gameserver.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "gameserver_s3" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.vpn_configs.arn}/team_*.ovpn"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.vpn_configs.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["team_*"]
    }
  }
}

resource "aws_iam_role_policy" "gameserver_s3" {
  name   = "ranger_gameserver_s3"
  role   = aws_iam_role.gameserver.id
  policy = data.aws_iam_policy_document.gameserver_s3.json
}

resource "aws_iam_instance_profile" "gameserver" {
  name = "ranger_gameserver"
  role = aws_iam_role.gameserver.name
}

# Admin role: base + read team_*.ovpn (so the `presign-vpn` operator script can
# generate signed S3 URLs for OOB distribution to teams).
resource "aws_iam_role" "admin" {
  name               = "ranger_admin"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "admin_ssm_core" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "admin_cwagent" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

data "aws_iam_policy_document" "admin_s3" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.vpn_configs.arn}/team_*.ovpn"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.vpn_configs.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["team_*"]
    }
  }
}

resource "aws_iam_role_policy" "admin_s3" {
  name   = "ranger_admin_s3"
  role   = aws_iam_role.admin.id
  policy = data.aws_iam_policy_document.admin_s3.json
}

resource "aws_iam_instance_profile" "admin" {
  name = "ranger_admin"
  role = aws_iam_role.admin.name
}

resource "aws_iam_role_policy" "vpn_server_s3" {
  name   = "ranger_vpn_server_s3"
  role   = aws_iam_role.vpn_server.id
  policy = data.aws_iam_policy_document.vpn_server_s3.json
}

resource "aws_iam_instance_profile" "vpn_server" {
  name = "ranger_vpn_server"
  role = aws_iam_role.vpn_server.name
}

# Vulnbox role: base + read its own config from the vpn_configs bucket.
# Uses a wildcard on the prefix since the team id is known only at apply-time
# in the team module; each vulnbox is free-standing in a private subnet with
# no cross-team network path, so restricting per-team at the IAM layer is belt-
# and-braces rather than load-bearing.
resource "aws_iam_role" "vulnbox" {
  name               = "ranger_vulnbox"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role_policy_attachment" "vulnbox_ssm_core" {
  role       = aws_iam_role.vulnbox.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "vulnbox_s3" {
  statement {
    actions = [
      "s3:GetObject",
    ]
    resources = [
      "${aws_s3_bucket.vpn_configs.arn}/vulnbox_*.ovpn",
    ]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.vpn_configs.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["vulnbox_*"]
    }
  }
}

resource "aws_iam_role_policy" "vulnbox_s3" {
  name   = "ranger_vulnbox_s3"
  role   = aws_iam_role.vulnbox.id
  policy = data.aws_iam_policy_document.vulnbox_s3.json
}

resource "aws_iam_instance_profile" "vulnbox" {
  name = "ranger_vulnbox"
  role = aws_iam_role.vulnbox.name
}
