/**
 * Internal DNS for the range.
 *
 * One private Route53 zone associated with both VPCs; CNAMEs for the
 * submission/scoreboard live on the gameserver.
 */

resource "aws_route53_zone" "ctf_internal" {
  name = "ctf.internal"

  vpc {
    vpc_id = aws_vpc.ranger_main.id
  }

  vpc {
    vpc_id = aws_vpc.ranger_teams.id
  }

  tags = {
    Name = "ranger_ctf_internal"
  }
}

resource "aws_route53_record" "gameserver" {
  zone_id = aws_route53_zone.ctf_internal.zone_id
  name    = "gameserver.ctf.internal"
  type    = "A"
  ttl     = 60
  records = [aws_instance.gameserver.private_ip]
}

resource "aws_route53_record" "submission" {
  zone_id = aws_route53_zone.ctf_internal.zone_id
  name    = "submission.ctf.internal"
  type    = "A"
  ttl     = 60
  records = [aws_instance.gameserver.private_ip]
}

resource "aws_route53_record" "scoreboard" {
  zone_id = aws_route53_zone.ctf_internal.zone_id
  name    = "scoreboard.ctf.internal"
  type    = "A"
  ttl     = 60
  records = [aws_instance.gameserver.private_ip]
}

resource "aws_route53_record" "checker" {
  zone_id = aws_route53_zone.ctf_internal.zone_id
  name    = "checker.ctf.internal"
  type    = "A"
  ttl     = 60
  records = [aws_instance.checker.private_ip]
}
