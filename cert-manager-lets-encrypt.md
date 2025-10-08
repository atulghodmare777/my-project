markdown# Complete HTTPS Flow: cert-manager + Let's Encrypt

A comprehensive guide explaining how cert-manager automates SSL certificate management in Kubernetes using Let's Encrypt.

---

## 🎯 The Goal

Enable users to securely access your application at `https://app.example.com` with automatically issued and renewed SSL certificates from Let's Encrypt, managed by cert-manager inside Kubernetes.

---

## 🧩 Key Components

| Component | Role | Namespace |
|-----------|------|-----------|
| **Let's Encrypt (CA)** | Public Certificate Authority that issues SSL certificates | Outside cluster |
| **cert-manager** | Kubernetes controller that automates certificate requests, renewals, and stores them as Secrets | `cert-manager` |
| **ClusterIssuer / Issuer** | Configuration that tells cert-manager how to request certs using ACME protocol | Cluster-wide or app namespace |
| **Ingress Controller** | Terminates HTTPS (decrypts SSL traffic) and routes HTTP internally | `ingress-nginx` |
| **Application + Ingress** | Your app deployment and ingress object defining external domain + TLS settings | Your app namespace (e.g., `my-app`) |

---

## 🔄 End-to-End Flow

### Step 1: Deploy an Ingress with HTTPS Annotation

Create an Ingress resource with TLS configuration:
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: myapp-ingress
  namespace: my-app
  annotations:
    kubernetes.io/ingress.class: nginx
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: app-example-com-tls  # cert-manager will create this Secret
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: myapp
            port:
              number: 80
Step 2: cert-manager Detects the Ingress
cert-manager continuously watches for:

Ingress objects with a tls section
The annotation cert-manager.io/cluster-issuer or cert-manager.io/issuer

It then initiates the certificate request process for app.example.com using the specified issuer.
Step 3: cert-manager Uses the Issuer Configuration
Your ClusterIssuer configuration:
yamlapiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    email: admin@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
    - http01:
        ingress:
          class: nginx
Key Points:

cert-manager communicates with Let's Encrypt using the ACME protocol
Stores an account key in Secret letsencrypt-prod-account-key in the cert-manager namespace
Uses HTTP-01 challenge method to prove domain ownership

Step 4: Let's Encrypt Challenges Domain Ownership
Let's Encrypt requires proof of domain control:

"Prove you control app.example.com by serving this token at:
http://app.example.com/.well-known/acme-challenge/<token>"

cert-manager automatically:

Creates temporary Challenge and Order objects in the same namespace as your Ingress
Spins up a temporary pod and Ingress route to respond to the token path
Since your DNS A record points to your LoadBalancer → Ingress → Cluster, Let's Encrypt successfully reaches the token

✅ Ownership verified
Step 5: Let's Encrypt Issues the Certificate
After successful verification, Let's Encrypt sends:

The signed certificate (tls.crt)
The private key (tls.key)

cert-manager then:

Creates a Kubernetes Secret of type kubernetes.io/tls in the same namespace as your Ingress

bashkubectl get secret -n my-app app-example-com-tls
Secret contents:
yamlData:
  tls.crt  → public certificate
  tls.key  → private key
This Secret is owned and managed by cert-manager (auto-renewed and updated).
Step 6: Ingress Controller Loads the Secret
Your Ingress Controller (e.g., NGINX):

Watches all Ingress resources
Reads the Secret app-example-com-tls from the same namespace
Loads tls.crt and tls.key into memory
Starts listening on port 443 for HTTPS traffic

Step 7: SSL Termination at Ingress Controller
When a user visits https://app.example.com:
Browser (HTTPS)
   ↓
[Load Balancer / External IP]
   ↓
Ingress Controller (NGINX)
   ↓  🔐 SSL TERMINATION HERE
HTTP (decrypted)
   ↓
Kubernetes Service
   ↓
App Pods
The Ingress Controller:

Presents the certificate (tls.crt)
Decrypts SSL traffic
Forwards plain HTTP to your backend service

Step 8: Automatic Renewal
cert-manager handles renewals automatically:

Monitors certificate expiration dates
When < 30 days remain, repeats the ACME challenge and renewal process
Updates the same Secret (app-example-com-tls)
Ingress Controller automatically reloads the new certificate without downtime


📦 Secret Storage Overview
Secret NamePurposeNamespaceCreated Byletsencrypt-prod-account-keyACME account key for Let's Encrypt authenticationcert-managercert-managerapp-example-com-tlsTLS certificate & private key for your appSame as Ingress (e.g., my-app)cert-managerTemporary challenge objectsFor ACME validationSame as Ingresscert-manager (auto-cleaned)

🔒 HTTP vs HTTPS Traffic
FlowDescriptionEncryptionHTTP (Port 80)Unencrypted traffic (used for Let's Encrypt validation or redirects)❌ NoneHTTPS (Port 443)Browser connects securely; Ingress presents certificate and decrypts✅ TLS Encrypted
Typical Configuration:

Port 80 → Redirects to HTTPS (443)
Port 443 → Handled by Ingress Controller using the TLS Secret


🗺️ Visual Architecture Diagram
                      ┌────────────────────┐
                      │ Let's Encrypt (CA) │
                      └────────┬───────────┘
                               │ ACME Protocol
                               ▼
                   ┌────────────────────────┐
                   │ cert-manager (in K8s)  │
                   ├────────────────────────┤
                   │ - Talks to ACME API    │
                   │ - Proves domain control│
                   │ - Creates Secrets      │
                   └────────┬───────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
  Secret: account key   Secret: TLS cert     Challenge objects
  (cert-manager ns)     (app ns)             (app ns, temporary)
        │                   │
        │                   ▼
        │            Ingress Controller
        │             (NGINX / Traefik)
        │                   │
        ▼                   ▼
Browser ──────HTTPS────────▶Ingress (terminates SSL)
                            │
                            ▼
                     App Service (HTTP)
                            │
                            ▼
                       App Pods

✅ Quick Reference Summary
StageComponentNamespaceWhat Happens1. TriggerIngress createdApp namespaceTriggers cert-manager2. Requestcert-manager contacts Let's Encryptcert-managerRequests cert via ACME3. ValidationChallenge validationApp namespacecert-manager proves domain control4. IssuanceCertificate issuedApp namespacecert-manager creates TLS Secret5. ActivationIngress loads SecretApp namespaceIngress terminates HTTPS6. RenewalAuto-renewalSame namespacescert-manager auto-renews & updates Secret

🚀 Getting Started

Install cert-manager:

bash   kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml

Create ClusterIssuer (update email):

bash   kubectl apply -f clusterissuer.yaml

Deploy your application with Ingress (include cert-manager annotations)
Verify certificate:

bash   kubectl get certificate -n my-app
   kubectl describe certificate -n my-app app-example-com-tls

📚 Additional Resources

cert-manager Documentation
Let's Encrypt Documentation
Kubernetes Ingress


Last Updated: October 2025

This Markdown file is now:
- ✨ Well-structured with clear sections
- 📊 Uses tables for better readability
- 🎨 Includes emojis for visual appeal
- 📝 Has proper code blocks with syntax highlighting
- 🗺️ Contains ASCII diagrams
- 📚 Includes a getting started section
- 🔗 Has resource links

Simply copy and paste this into your GitHub repository as `README.md` or `cert-manager-guide.md`, and it will render beautifully!
