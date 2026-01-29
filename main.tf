# 1. Définition du fournisseur (le Cloud que l'on va utiliser)
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0" # Utilise une version stable récente
    }
  }
}

# 2. Configuration de la connexion à AWS
provider "aws" {
  region = "eu-west-3" 
}
# 3. Aucune ressource n'est déclarée ici. 
# Le fichier est "vide" de toute infrastructure réelle.

# --- SECTION 4. Création de l'utilisateur pour la Pipeline (IAM User) ---

# 1. Création de l'utilisateur réel sur AWS
resource "aws_iam_user" "pipeline_user" {
  name = "infoline-pipeline-user" # Le nom que nous avons choisi ensemble
  path = "/system/"

  tags = {
    Project = "infoline-2026"
    Owner   = "DevOps-Team"
  }
}

# 2. Création des clés d'accès programmatiques (Access Key & Secret Key)
resource "aws_iam_access_key" "pipeline_key" {
  user = aws_iam_user.pipeline_user.name
}

# 3. Attribution des droits d'administrateur (nécessaire pour Terraform)
resource "aws_iam_user_policy_attachment" "pipeline_admin_access" {
  user       = aws_iam_user.pipeline_user.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# --- SECTION 5. Outputs (pour récupérer les clés après l'apply) ---

output "pipeline_user_access_key" {
  value     = aws_iam_access_key.pipeline_key.id
  sensitive = true
}

output "pipeline_user_secret_key" {
  value     = aws_iam_access_key.pipeline_key.secret
  sensitive = true
}
# --- SECTION 6. Création du Réseau (VPC) ---
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name    = "infoline-vpc"
    Project = "infoline-2026"
  }
}

# --- SECTION 7. Création du Sous-réseau (Subnet) ---
resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-3a" # Vérifie que c'est bien dans ta région

  tags = {
    Name    = "infoline-public-subnet"
    Project = "infoline-2026"
  }
}
# --- SECTION 8. Création du Registre d'images (ECR) ---
resource "aws_ecr_repository" "infoline_repo" {
  name                 = "infoline-app-repo"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    # Analyse automatiquement les vulnérabilités lors du push
    scan_on_push = true
  }

  tags = {
    Name    = "infoline-ecr"
    Project = "infoline-2026"
  }
}
