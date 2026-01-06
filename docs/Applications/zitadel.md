# Zitadel - Identity and Access Management

Zitadel is an open-source identity and access management (IAM) solution that provides authentication and authorization services. It implements modern standards like OAuth 2.0, OpenID Connect (OIDC), and SAML 2.0.

## Overview

Zitadel serves as the central identity provider for the burginfra infrastructure, managing:

- **User Authentication**: Login, MFA, passwordless authentication
- **User Management**: User profiles, roles, and permissions
- **Application Integration**: OAuth2/OIDC for SSO
- **API Access**: Service accounts and machine-to-machine authentication
- **Organizations**: Multi-tenancy support

## Key Features

### Authentication
- Username/Password authentication
- Multi-Factor Authentication (MFA)
- Passwordless authentication (WebAuthn, FIDO2)
- Social login providers (Google, GitHub, etc.)
- LDAP/Active Directory integration

### Authorization
- Role-Based Access Control (RBAC)
- Fine-grained permissions
- OAuth 2.0 scopes
- Custom authorization policies

### Standards Compliance
- OAuth 2.0
- OpenID Connect (OIDC)
- SAML 2.0
- SCIM 2.0 (for user provisioning)

### Multi-Tenancy
- Organizations for tenant isolation
- Separate branding per organization
- Delegated administration

### Developer Experience
- REST and gRPC APIs
- SDKs for multiple languages
- Comprehensive documentation
- Admin UI and user portal

## Architecture

Zitadel consists of:

1. **Zitadel Server**: Core IAM service
2. **Login UI**: User-facing authentication interface
3. **Admin Console**: Management interface
4. **PostgreSQL Database**: Data persistence
5. **Event Store**: Audit trail and event sourcing

## Access

### Staging Environment

- **URL**: `https://iam.staging.burgdev.ch`
- **Admin Console**: `https://iam.staging.burgdev.ch/ui/console`
- **User Account**: `https://iam.staging.burgdev.ch/ui/login/user`

## Initial Setup

### First Login

After deployment, access the admin console at the URL above. The initial admin user is created during the first setup wizard.

### Create Initial Admin User

1. Navigate to the Zitadel URL
2. Follow the setup wizard
3. Create the first admin user:
   - Username: `admin` (or your preferred username)
   - Password: Set a strong password
   - Email: Your admin email address

### Admin Console

The admin console provides:
- User management
- Application registration
- Organization settings
- Branding customization
- Audit logs

## Application Integration

### Register an Application

1. Log into the Admin Console
2. Navigate to **Projects** → Create new project
3. Click **New Application**
4. Choose application type:
   - **Web**: For web applications using OAuth2/OIDC
   - **Native**: For mobile/desktop apps
   - **API**: For backend services and machine-to-machine
   - **User Agent**: For SPAs (single-page applications)

### OAuth2/OIDC Configuration

For a web application:

1. **Redirect URIs**: Add your application's callback URLs
2. **Post-Logout Redirect URIs**: Where to redirect after logout
3. **Grant Types**: Authorization Code (recommended)
4. **Response Type**: Code
5. **PKCE**: Enable for enhanced security

You'll receive:
- **Client ID**: Public identifier for your application
- **Client Secret**: Confidential secret (keep secure)

### Example Integration

**Discovery URL**:
```
https://iam.staging.burgdev.ch/.well-known/openid-configuration
```

**Authorization Endpoint**:
```
https://iam.staging.burgdev.ch/oauth/v2/authorize
```

**Token Endpoint**:
```
https://iam.staging.burgdev.ch/oauth/v2/token
```

**UserInfo Endpoint**:
```
https://iam.staging.burgdev.ch/oidc/v1/userinfo
```

### Authorization Code Flow Example

```bash
# 1. Redirect user to authorization endpoint
https://iam.staging.burgdev.ch/oauth/v2/authorize?
  client_id=YOUR_CLIENT_ID
  &redirect_uri=https://yourapp.com/callback
  &response_type=code
  &scope=openid profile email
  &state=RANDOM_STATE

# 2. User authenticates and approves

# 3. Zitadel redirects to your callback with code
https://yourapp.com/callback?code=AUTHORIZATION_CODE&state=RANDOM_STATE

# 4. Exchange code for tokens
curl -X POST https://iam.staging.burgdev.ch/oauth/v2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code" \
  -d "code=AUTHORIZATION_CODE" \
  -d "redirect_uri=https://yourapp.com/callback" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET"

# Response:
{
  "access_token": "...",
  "id_token": "...",
  "refresh_token": "...",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

## User Management

### Create Users

Via Admin Console:
1. Navigate to **Users**
2. Click **New User**
3. Fill in user details
4. Assign roles/permissions
5. Send invitation email

Via API:
```bash
curl -X POST https://iam.staging.burgdev.ch/management/v1/users/human \
  -H "Authorization: Bearer YOUR_PAT" \
  -H "Content-Type: application/json" \
  -d '{
    "userName": "user@example.com",
    "profile": {
      "firstName": "John",
      "lastName": "Doe"
    },
    "email": {
      "email": "user@example.com",
      "isEmailVerified": false
    }
  }'
```

### Roles and Permissions

Zitadel uses a role-based access control model:

- **Project Roles**: Define custom roles per project
- **Grants**: Assign roles to users
- **Authorizations**: Check permissions in your application

## Service Accounts (Machine Users)

For backend services and API access:

1. Navigate to **Users** → **Service Users**
2. Create a new service user
3. Generate a Personal Access Token (PAT) or use Client Credentials
4. Use the token for API authentication

## Organizations

Organizations provide multi-tenancy:

- Each organization has isolated users
- Separate branding and policies
- Delegated administration
- Shared applications across organizations

## Branding Customization

Customize the login UI:

1. Navigate to **Organization Settings** → **Branding**
2. Upload logo and favicon
3. Customize colors and themes
4. Set custom login text
5. Add privacy policy and terms of service links

## Security Best Practices

### Authentication
- **Enable MFA**: Require multi-factor authentication
- **Passwordless**: Use WebAuthn/FIDO2 for stronger security
- **Password Policies**: Enforce strong password requirements
- **Session Management**: Configure appropriate session timeouts

### Authorization
- **Least Privilege**: Grant minimum necessary permissions
- **Regular Audits**: Review user roles and access
- **Service Accounts**: Use dedicated accounts for services

### Application Security
- **PKCE**: Always use PKCE for public clients
- **State Parameter**: Prevent CSRF attacks
- **Token Validation**: Verify ID tokens and access tokens
- **HTTPS Only**: Never use HTTP in production

### Monitoring
- **Audit Logs**: Monitor authentication events
- **Failed Login Attempts**: Watch for brute force attacks
- **Token Usage**: Track API access patterns

## API Access

### Personal Access Tokens (PAT)

For programmatic access:

1. Navigate to your user profile
2. Go to **Personal Access Tokens**
3. Create a new token
4. Store securely (shown only once)

Usage:
```bash
curl https://iam.staging.burgdev.ch/management/v1/orgs/me \
  -H "Authorization: Bearer YOUR_PAT"
```

### Client Credentials Flow

For machine-to-machine authentication:

```bash
curl -X POST https://iam.staging.burgdev.ch/oauth/v2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -d "scope=openid"
```

## Common Use Cases

### Single Sign-On (SSO)
Implement SSO across multiple applications using OAuth2/OIDC. Users log in once and access all connected applications.

### API Gateway Authentication
Use Zitadel as the authentication provider for your API gateway. Validate access tokens before proxying requests.

### Multi-Tenant SaaS
Use organizations to isolate customer data. Each customer gets their own organization with isolated users.

### Mobile App Authentication
Use OAuth2 with PKCE for secure authentication in mobile applications.

### Service-to-Service Authentication
Use client credentials flow for backend services to authenticate with each other.

## Maintenance

### User Cleanup
Periodically review and remove inactive users.

### Token Rotation
Regularly rotate service account tokens and client secrets.

### Audit Review
Review audit logs for suspicious activity.

### Backup
Ensure database backups are configured (see Kubernetes documentation).

## Troubleshooting

### Cannot Log In
- Verify user exists and is active
- Check password policy requirements
- Review failed login attempts in audit log

### Application Integration Issues
- Verify redirect URIs match exactly
- Check client ID and secret
- Ensure correct grant types are configured
- Validate token expiration

### Performance Issues
- Check database performance
- Review connection pool settings
- Monitor resource usage (CPU, memory)

## Resources

### Official Documentation
- **Main Docs**: https://zitadel.com/docs
- **API Reference**: https://zitadel.com/docs/apis/introduction
- **Quickstarts**: https://zitadel.com/docs/quickstarts/introduction
- **Examples**: https://github.com/zitadel/zitadel/tree/main/examples

### SDKs
- **JavaScript/TypeScript**: `@zitadel/client`
- **Go**: `github.com/zitadel/zitadel-go`
- **Python**: `zitadel-python`
- **.NET**: `Zitadel.Client`

### Community
- **GitHub**: https://github.com/zitadel/zitadel
- **Discord**: https://zitadel.com/chat
- **Discussions**: https://github.com/zitadel/zitadel/discussions

### Standards
- **OAuth 2.0**: https://oauth.net/2/
- **OpenID Connect**: https://openid.net/connect/
- **PKCE**: https://oauth.net/2/pkce/
