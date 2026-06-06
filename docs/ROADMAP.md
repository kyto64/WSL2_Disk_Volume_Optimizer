# Roadmap

This roadmap captures planned improvements for making WSL2 Disk Volume Optimizer safer, easier to validate, and easier to distribute. Items are not guaranteed release commitments, but they define the current direction of the project.

## Planned

### Dry-run Mode

Add a `-WhatIf` or `-DryRun` mode that lists detected VHDX files, estimated sizes, planned commands, and safety warnings without shutting down WSL or compacting anything.

### PowerShell Module

Package the core logic as a PowerShell module (`.psm1`) with public functions for discovery, safety checks, and compaction. This would make the tool easier to install, test, and reuse.

### CI Validation

Add GitHub Actions for static validation. Initial checks should include PowerShell syntax validation and PSScriptAnalyzer.

### Tests

Add Pester tests for path detection, administrator checks, fallback selection, and logging behavior. The first test suite should avoid touching real VHDX files.

### Better Docker Desktop Detection

Improve support for Docker Desktop path variations across versions and installation layouts. The tool should clearly report which Docker Desktop VHDX files were detected and which were skipped.

### Interactive VHDX Selection

Add interactive per-path selection so users can choose which detected VHDX files to compact during a manual run.

### Package Manager Support

Evaluate distribution through `winget` and Scoop after the release artifacts and installation flow are stable.

### Signed Release Artifacts

Investigate Authenticode signing for release scripts and batch files so users can verify that artifacts are published by the maintainer.

## Under Consideration

### GUI or TUI Frontend

A small GUI or terminal UI could make safety checks and result reporting clearer for users who are not comfortable with PowerShell.

### JSON Output

Add structured output for automation, including detected files, before/after sizes, selected compaction method, and per-file status.

## Completed

### Custom VHDX Path Support

Added registered WSL distribution detection and an explicit `-VHDPath` option for custom VHDX locations that are not under the default `%LOCALAPPDATA%` paths.

### Release Checklist

Add a release checklist covering documentation, safety notes, version tags, checksums, release notes, and artifact verification.

## Issue Tracker

Roadmap items are tracked as GitHub Issues with the `roadmap` label where possible. Contributions are welcome, especially for tests, documentation, and safety improvements.
