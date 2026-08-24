data "oci_objectstorage_namespace" "this" {
  compartment_id = var.compartment_ocid
}

resource "oci_objectstorage_bucket" "datapack" {
  access_type    = var.datapack_bucket_public_access_type
  compartment_id = var.compartment_ocid
  freeform_tags  = local.common_tags
  name           = var.datapack_bucket_name
  namespace      = data.oci_objectstorage_namespace.this.namespace
  storage_tier   = "Standard"
  versioning     = "Enabled"
}

resource "oci_objectstorage_bucket" "datapack_candidate" {
  access_type    = "NoPublicAccess"
  compartment_id = var.compartment_ocid
  freeform_tags  = local.common_tags
  name           = var.datapack_candidate_bucket_name
  namespace      = data.oci_objectstorage_namespace.this.namespace
  storage_tier   = "Standard"
  versioning     = "Disabled"
}

resource "oci_objectstorage_object_lifecycle_policy" "datapack_candidate" {
  bucket    = oci_objectstorage_bucket.datapack_candidate.name
  namespace = data.oci_objectstorage_namespace.this.namespace

  rules {
    action      = "DELETE"
    is_enabled  = true
    name        = "delete-candidate-objects-after-14-days"
    target      = "objects"
    time_amount = 14
    time_unit   = "Days"

    object_name_filter {
      inclusion_prefixes = [var.datapack_candidate_object_prefix]
    }
  }
}

resource "oci_identity_user" "datapack_candidate_publisher" {
  provider = oci.identity_home

  compartment_id = var.tenancy_ocid
  description    = "Dedicated publisher for immutable data pack candidates."
  email          = var.datapack_candidate_publisher_email
  name           = "${var.name_prefix}-datapack-candidate-publisher"
}

resource "oci_identity_group" "datapack_candidate_publishers" {
  provider = oci.identity_home

  compartment_id = var.tenancy_ocid
  description    = "Dedicated publishers for immutable data pack candidates."
  name           = "${var.name_prefix}-datapack-candidate-publishers"
}

resource "oci_identity_user_group_membership" "datapack_candidate_publisher" {
  provider = oci.identity_home

  group_id = oci_identity_group.datapack_candidate_publishers.id
  user_id  = oci_identity_user.datapack_candidate_publisher.id
}

resource "oci_identity_customer_secret_key" "datapack_candidate_publisher" {
  provider = oci.identity_home

  display_name = "${var.name_prefix}-datapack-candidate-publisher"
  user_id      = oci_identity_user.datapack_candidate_publisher.id
}

resource "oci_identity_policy" "datapack_candidate_publisher" {
  provider = oci.identity_home

  compartment_id = var.tenancy_ocid
  description    = "Candidate publisher may create and read only candidate objects in its dedicated bucket."
  name           = "${var.name_prefix}-datapack-candidate-publisher"
  statements = [
    "Allow group ${oci_identity_group.datapack_candidate_publishers.name} to {OBJECT_CREATE, OBJECT_READ} in compartment id ${var.compartment_ocid} where all {target.bucket.name = '${var.datapack_candidate_bucket_name}', target.object.name = '${var.datapack_candidate_object_prefix}*'}",
  ]
}

resource "oci_identity_customer_secret_key" "datapack_publisher" {
  provider = oci.identity_home

  display_name = "${var.name_prefix}-datapack-publisher"
  user_id      = var.user_ocid
}
