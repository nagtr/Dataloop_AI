#This file will have teraform configuration

# main.tf



provider "google" {

  credentials = file("/home/nagendra/Dataloop_assignment/data-loop-assignment-d459f3412681.json")

  project     = "data-loop-assignment"

  region      = "us-central1-f"

}



# GKE cluster

data "google_container_engine_versions" "gke_version" {

  location = "us-central1"

  version_prefix = "1.27."

}



# VPC

#resource "google_compute_network" "vpc" {

# name                    = "data-loop-vpc"

#  auto_create_subnetworks = "false"

#}



# Subnet

#resource "google_compute_subnetwork" "subnet" {

#  name          = "data-loop-subnet"

#  region        = "us-central1"

#  network       = google_compute_network.vpc.name

#  ip_cidr_range = "10.10.0.0/24"

#}





# Create a GKE cluster

resource "google_container_cluster" "data-loop-assgn" {

  name     = "data-loop-assgn"

  location = "us-central1"

  remove_default_node_pool = true

  initial_node_count = 1

  

  #network    = google_compute_network.vpc.name

  #subnetwork = google_compute_subnetwork.subnet.name

  node_config {



    labels = {

      env = "prod"

    }



    # preemptible  = true

    machine_type = "e2-medium"

    disk_size_gb = 30

  }

}



resource "google_container_node_pool" "data-loop-assgn_nodes" {

  name       = google_container_cluster.data-loop-assgn.name

  location   = "us-central1"

  cluster    = google_container_cluster.data-loop-assgn.name

  

  version = data.google_container_engine_versions.gke_version.release_channel_latest_version["STABLE"]

  node_count = 1



  node_config {



    labels = {

      env = "prod"

    }



    # preemptible  = true

    machine_type = "e2-medium"

    disk_size_gb = 30

  }

}



#Configure kubectl to use the created cluster

resource "null_resource" "configure_kubectl" {

  depends_on = [google_container_cluster.data-loop-assgn]



  provisioner "local-exec" {

    command = "gcloud container clusters get-credentials data-loop-assgn --region us-central1"

  }

}



 provider "kubernetes" {

   config_path    = "~/.kube/config"

   

   host     = "https://${google_container_cluster.data-loop-assgn.endpoint}"

   client_certificate     = google_container_cluster.data-loop-assgn.master_auth.0.client_certificate

   client_key             = google_container_cluster.data-loop-assgn.master_auth.0.client_key

   cluster_ca_certificate = base64decode(google_container_cluster.data-loop-assgn.master_auth.0.cluster_ca_certificate)

 }



# Create namespaces

resource "kubernetes_namespace" "services_namespace" {



#  depends_on = [null_resource.get-credentials]



  metadata {

    name = "services"

  }

}



resource "kubernetes_namespace" "monitoring_namespace" {

  metadata {

    name = "monitoring"

  }

}



# Deploy Nginx to "services" namespace

resource "kubernetes_deployment" "nginx" {

  metadata {

    name      = "nginx"

    namespace = kubernetes_namespace.services_namespace.metadata[0].name

  }



  spec {

    replicas = 1



    selector {

      match_labels = {

        app = "nginx"

      }

    }



    template {

      metadata {

        labels = {

          app = "nginx"

        }

      }



      spec {

        container {

          name  = "nginx"

          image = "nginx:latest"

          port {

            container_port = 80

          }

        }

      }

    }

  }

}



# Deploy Prometheus + Grafana to "monitoring" namespace

resource "helm_release" "prometheus_grafana" {

  name       = "prometheus-grafana"

  namespace  = kubernetes_namespace.monitoring_namespace.metadata[0].name

  repository = "https://prometheus-community.github.io/helm-charts"

  chart      = "prometheus"

  version    = "25.1.0"



  set {

    name  = "server.persistentVolume.enabled"

    value = "false"

  }

}



# Expose Nginx and Grafana to the internet

resource "kubernetes_service" "nginx_service" {

  metadata {

    name      = "nginx-service"

    namespace = kubernetes_namespace.services_namespace.metadata[0].name

  }



  spec {

    selector = {

      app = kubernetes_deployment.nginx.spec[0].template[0].metadata[0].labels["app"]

    }



    port {

      protocol    = "TCP"

      port        = 80

      target_port = 80

    }



    type = "LoadBalancer"

  }

}



resource "kubernetes_service" "grafana_service" {

  metadata {

    name      = "grafana-service"

    namespace = kubernetes_namespace.monitoring_namespace.metadata[0].name

  }



  spec {

    port {

      protocol    = "TCP"

      port        = 80

      target_port = 3000

    }



    type = "LoadBalancer"

  }

}

