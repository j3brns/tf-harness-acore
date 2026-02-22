import os
import sys


def test_ssm_durability():
    print("[Test 1] Verifying SSM Durability in Foundation Module...")
    foundation_path = "terraform/modules/agentcore-foundation"
    for filename in os.listdir(foundation_path):
        if filename.endswith(".tf"):
            with open(os.path.join(foundation_path, filename), "r") as f:
                content = f.read()
                if 'data "external"' in content:
                    if filename == "gateway.tf" or filename == "identity.tf":
                        raise Exception(f"FAILED: 'data \"external\"' still exists in {filename}")

    with open("terraform/modules/agentcore-foundation/gateway.tf", "r") as f:
        content = f.read()
        if 'data "aws_ssm_parameter" "gateway_id"' not in content:
            raise Exception("FAILED: SSM data source missing in gateway.tf")

    print("  PASS: Brittle local state dependencies removed.")


def test_arch_logic():
    print("[Test 2] Verifying Architecture Logic in packaging.tf...")
    with open("terraform/modules/agentcore-runtime/packaging.tf", "r") as f:
        content = f.read()
        if 'PLATFORM="manylinux2014_x86_64"' not in content:
            raise Exception("FAILED: Default platform logic missing")
        if 'if [ "${var.lambda_architecture}" == "arm64" ]' not in content:
            raise Exception("FAILED: ARM64 architecture check missing")
        if 'PLATFORM="manylinux2014_aarch64"' not in content:
            raise Exception("FAILED: ARM64 platform logic missing")
    print("  PASS: Architecture-aware platform selection logic verified in code.")


def test_zip_exclusions():
    print("[Test 3] Verifying Hardened Zip Exclusions...")
    with open("terraform/modules/agentcore-runtime/packaging.tf", "r") as f:
        content = f.read()
        required_exclusions = ["*.env*", "*.tfvars*", ".terraform/*", ".venv/*", "venv/*", "tests/*", "node_modules/*"]
        for exc in required_exclusions:
            if exc not in content:
                raise Exception(f"FAILED: Exclusion pattern '{exc}' missing from packaging.tf")
    print("  PASS: Hardened zip exclusion patterns verified in code.")


def test_cli_output_dir_creation():
    print("[Test 4] Verifying CLI modules create local .terraform output directories...")

    required_files = [
        "terraform/modules/agentcore-foundation/gateway.tf",
        "terraform/modules/agentcore-foundation/identity.tf",
        "terraform/modules/agentcore-governance/evaluations.tf",
        "terraform/modules/agentcore-governance/policy.tf",
        "terraform/modules/agentcore-runtime/inference_profile.tf",
        "terraform/modules/agentcore-runtime/runtime.tf",
        "terraform/modules/agentcore-tools/browser.tf",
        "terraform/modules/agentcore-tools/code_interpreter.tf",
    ]

    for path in required_files:
        with open(path, "r") as f:
            content = f.read()
            if 'mkdir -p "${path.module}/.terraform"' not in content:
                raise Exception(f"FAILED: {path} does not create .terraform output directory before file writes")

    print("  PASS: CLI module local output directory creation is enforced.")


def test_provider_freeze_point_pin():
    print("[Test 5] Verifying AWS provider freeze-point pin...")
    with open("terraform/versions.tf", "r") as f:
        content = f.read()
        if 'source  = "hashicorp/aws"' not in content:
            raise Exception('FAILED: hashicorp/aws provider source not found in terraform/versions.tf')
        if 'version = "~> 6.33.0"' not in content:
            raise Exception('FAILED: AWS provider freeze-point pin (~> 6.33.0) missing in terraform/versions.tf')
    print("  PASS: AWS provider freeze-point pin verified.")


def test_native_gateway_pilot_guards():
    print("[Test 6] Verifying native gateway pilot compatibility guards...")

    with open("terraform/modules/agentcore-foundation/gateway.tf", "r") as f:
        content = f.read()
        if 'var.gateway_search_type == "HYBRID" ? "SEMANTIC" : var.gateway_search_type' not in content:
            raise Exception("FAILED: native gateway search_type compatibility guard missing in gateway.tf")

    with open("terraform/modules/agentcore-foundation/variables.tf", "r") as f:
        content = f.read()
        if 'variable "use_native_gateway"' not in content:
            raise Exception('FAILED: module variable "use_native_gateway" missing in foundation variables.tf')

    with open("terraform/variables.tf", "r") as f:
        content = f.read()
        if 'variable "use_native_gateway"' not in content:
            raise Exception('FAILED: root variable "use_native_gateway" missing in terraform/variables.tf')

    print("  PASS: Native gateway pilot guards verified.")


if __name__ == "__main__":
    try:
        test_ssm_durability()
        test_arch_logic()
        test_zip_exclusions()
        test_cli_output_dir_creation()
        test_provider_freeze_point_pin()
        test_native_gateway_pilot_guards()
        print("\nAll remediation integrity tests PASSED successfully.")
    except Exception as e:
        print("\nREMEDIATION TEST FAILED: " + str(e))
        sys.exit(1)
