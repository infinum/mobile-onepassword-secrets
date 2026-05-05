#!/usr/bin/env bash
# shellcheck disable=SC2034
# (vars are consumed by utils.sh / read.sh / write.sh after sourcing)

# config.sh - Shared configuration for 1password scripts

#########################################################
#                 1PASSWORD CONFIGURATION               #
#                                                       #
#   Edit this file to configure vaults and mappings     #
#                                                       #
#########################################################

# Local directory where secret files live
path="ProjectName/SupportingFiles/Vault"

# Known environments (used for filename validation in write.sh and the "*" shortcut below)
environments=(production staging)

# Available 1password vaults for this project (must match vaults in 1Password account)
vaults=("project-projectname-ios" "project-projectname-ios-staging")

# Files to fetch from 1Password.
# Format per entry: "filename:env1,env2,..." or "filename:*" for all environments.
# read.sh expands each into <basename>.<env>.<ext> documents.
# Example: "Keys.swift:*" -> Keys.production.swift, Keys.staging.swift
files=(
    "Keys.swift:*"
)

# File-to-vault mapping. Format per entry: "glob_pattern:vault".
# First match wins. Used by both read.sh and write.sh.
file_vaults=(
    "*.staging.*:project-projectname-ios-staging"
    "*.production.*:project-projectname-ios"
)
