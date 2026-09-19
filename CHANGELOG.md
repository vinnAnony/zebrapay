# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-19

### Added

- Initial release.
- M-Pesa (Daraja 3.0) gateway: STK Push, B2C, B2B, Transaction Status,
  Account Balance, and Reversal.
- `ZebraPay.WebhookPlug` for handling gateway callbacks in Phoenix apps.
- `ZebraPay.Gateway` behaviour for adding new payment gateways.
- Unified `ZebraPay.Response` struct across gateway operations.
- OAuth token caching for M-Pesa via `ZebraPay.TokenCache`.
