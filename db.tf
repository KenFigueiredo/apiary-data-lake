/**
 * Copyright (C) 2018-2020 Expedia, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */

resource "aws_db_subnet_group" "apiarydbsg" {
  count       = "${var.external_database_host == "" ? 1 : 0}"
  name        = "${local.instance_alias}-dbsg"
  subnet_ids  = var.private_subnets
  description = "Apiary DB Subnet Group"

  tags = "${merge(map("Name", "Apiary DB Subnet Group"), var.apiary_tags)}"
}

resource "aws_security_group" "db_sg" {
  count  = "${var.external_database_host == "" ? 1 : 0}"
  name   = "${local.instance_alias}-db"
  vpc_id = "${var.vpc_id}"
  tags   = "${var.apiary_tags}"

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${data.aws_vpc.apiary_vpc.cidr_block}"]
    self        = true
  }

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = "${var.ingress_cidr}"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    self        = true
  }
}

resource "random_id" "snapshot_id" {
  count       = "${var.external_database_host == "" ? 1 : 0}"
  byte_length = 8
}

resource "random_string" "db_master_password" {
  count   = "${var.external_database_host == "" ? 1 : 0}"
  length  = 16
  special = false
}

resource "aws_rds_cluster" "apiary_cluster" {
  count                               = "${var.external_database_host == "" ? 1 : 0}"
  cluster_identifier                  = "${local.instance_alias}-cluster"
  database_name                       = "${var.apiary_database_name}"
  master_username                     = "${var.db_master_username}"
  master_password                     = "${random_string.db_master_password[0].result}"
  backup_retention_period             = "${var.db_backup_retention}"
  preferred_backup_window             = "${var.db_backup_window}"
  preferred_maintenance_window        = "${var.db_maintenance_window}"
  db_subnet_group_name                = "${aws_db_subnet_group.apiarydbsg[0].name}"
  vpc_security_group_ids              = compact(concat(list(aws_security_group.db_sg[0].id), var.apiary_rds_additional_sg))
  tags                                = "${var.apiary_tags}"
  final_snapshot_identifier           = "${local.instance_alias}-cluster-final-${random_id.snapshot_id[0].hex}"
  iam_database_authentication_enabled = true
  apply_immediately                   = var.db_apply_immediately

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_instance" "apiary_cluster_instance" {
  count                = "${var.external_database_host == "" ? var.db_instance_count : 0}"
  identifier           = "${local.instance_alias}-instance-${count.index}"
  cluster_identifier   = "${aws_rds_cluster.apiary_cluster[0].id}"
  instance_class       = "${var.db_instance_class}"
  db_subnet_group_name = "${aws_db_subnet_group.apiarydbsg[0].name}"
  publicly_accessible  = false
  tags                 = "${var.apiary_tags}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "random_string" "secret_seed_slug" {
  length  = 8
  special = false
}

resource "aws_secretsmanager_secret" "apiary_mysql_master_credentials" {
  name = "apiary_db_master_user_${random_string.secret_seed_slug.result}"
  tags = var.apiary_tags
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "apiary_mysql_master_credentials" {
  secret_id     = aws_secretsmanager_secret.apiary_mysql_master_credentials.id
  secret_string = jsonencode(
    map(
      "username", var.db_master_username,
      "password", random_string.db_master_password[0].result
    )
  )
}