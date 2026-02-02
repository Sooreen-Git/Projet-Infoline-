# --- SECTION 1. Fournisseur ---
terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }
}

provider "aws" { region = "eu-west-3" }

# --- SECTION 2. Utilisateur IAM (À reconstruire) ---
resource "aws_iam_user" "pipeline_user" {
  name = "infoline-pipeline-user"
  path = "/system/"
}

resource "aws_iam_access_key" "pipeline_key" {
  user = aws_iam_user.pipeline_user.name
}

resource "aws_iam_user_policy_attachment" "pipeline_admin_access" {
  user       = aws_iam_user.pipeline_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- SECTION 3. Réseau (À reconstruire) ---
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "infoline-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-3a"
  map_public_ip_on_launch = true
}

# --- SECTION 4. ECR (On le garde et on le gère) ---
resource "aws_ecr_repository" "infoline_repo" {
  name                 = "infoline-app-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true # Permet à Terraform de supprimer si besoin même s'il y a des images
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_ecr_lifecycle_policy" "infoline_policy" {
  repository = aws_ecr_repository.infoline_repo.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1, selection = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 1 },
      action = { type = "expire" }
    }]
  })
}

# --- SECTION 5. ECS (Elastic Container Service) ---

# 1. Rôle IAM pour l'exécution des tâches ECS (Indispensable pour Fargate)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "infoline-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

# Attachement de la politique standard AWS pour l'exécution ECS
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# 2. Le Cluster
resource "aws_ecs_cluster" "main" {
  name = "infoline-cluster"
}

# 3. Task Definition (Mise à jour avec le nouveau rôle)
resource "aws_ecs_task_definition" "app" {
  family                   = "infoline-app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  
  # On utilise l'ARN du rôle qu'on vient de créer au-dessus
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name      = "infoline-app"
    image     = "${aws_ecr_repository.infoline_repo.repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
    }]
  }])
}

# 4. Le Service
resource "aws_ecs_service" "main" {
  name            = "infoline-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.public.id]
    assign_public_ip = true
  }
}

# --- SECTION 6. AWS Lambda (Serverless) ---

# 1. Rôle IAM pour la Lambda
resource "aws_iam_role" "lambda_role" {
  name = "infoline-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# 2. La fonction Lambda
resource "aws_lambda_function" "infoline_lambda" {
  filename      = "function_payload.zip"
  function_name = "infoline-hello-function"
  role          = aws_iam_role.lambda_role.arn
  handler       = "hello_infoline.handler"
  runtime       = "python3.9"

  # Pour détecter les changements de code dans le zip
  source_code_hash = filebase64sha256("function_payload.zip")
}

# Output pour confirmer la création
output "lambda_arn" {
  value = aws_lambda_function.infoline_lambda.arn
}
