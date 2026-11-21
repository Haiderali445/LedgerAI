# LedgerAI Backend API

ASP.NET Core Web API (.NET 9) host for the LedgerAI application.

## NuGet Package Manifest
- `Microsoft.AspNetCore.OpenApi` (9.0.x) — OpenAPI specification generation
- `Scalar.AspNetCore` (1.2.x) — Modern interactive API documentation UI
- `Npgsql.EntityFrameworkCore.PostgreSQL` (9.0.x) — PostgreSQL provider for EF Core
- `Microsoft.EntityFrameworkCore.Design` (9.0.x) — Design-time tools for migrations

## Configuration Settings
Configure database connections and integration credentials in `appsettings.json` / `appsettings.Development.json`:
- `ConnectionStrings:DefaultConnection`: PostgreSQL connection string with multi-tenant RLS support
- `JwtSettings`: Secret, Issuer, Audience, and token expiry configurations
- `GroqSettings`: Primary LLM credentials, model identifiers, and timeout configs
- `WhatsAppSettings`: Meta WhatsApp Cloud API credentials, access tokens, and webhook verification tokens

## Verification Endpoints
- **Metadata / Health Endpoint:** `GET /api/metadata`
- **Scalar API Documentation:** `GET /scalar/v1`
- **OpenAPI Document:** `GET /openapi/v1.json`
