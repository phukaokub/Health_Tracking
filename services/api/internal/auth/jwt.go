package auth

import (
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"math/big"
	"strings"
	"time"
)

type User struct {
	ID    string
	Email string
}
type contextKey struct{}

func WithUser(ctx context.Context, user User) context.Context {
	return context.WithValue(ctx, contextKey{}, user)
}
func UserFromContext(ctx context.Context) (User, bool) {
	u, ok := ctx.Value(contextKey{}).(User)
	return u, ok
}

type JWKS struct {
	Keys []JWK `json:"keys"`
}
type JWK struct {
	Kid string `json:"kid"`
	Kty string `json:"kty"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
	Crv string `json:"crv"`
	X   string `json:"x"`
	Y   string `json:"y"`
}

type Verifier struct {
	issuer   string
	audience string
	keys     map[string]crypto.PublicKey
	now      func() time.Time
}

func NewVerifier(issuer, audience string, jwks JWKS) (*Verifier, error) {
	keys := map[string]crypto.PublicKey{}
	for _, key := range jwks.Keys {
		if key.Kid == "" {
			continue
		}
		var pub crypto.PublicKey
		var err error
		switch key.Kty {
		case "RSA":
			pub, err = rsaPublicKey(key.N, key.E)
		case "EC":
			pub, err = ecdsaPublicKey(key.Crv, key.X, key.Y)
		default:
			continue
		}
		if err != nil {
			return nil, err
		}
		keys[key.Kid] = pub
	}
	if len(keys) == 0 {
		return nil, errors.New("auth: jwks has no usable rsa keys")
	}
	return &Verifier{issuer: issuer, audience: audience, keys: keys, now: time.Now}, nil
}

type claims struct {
	Subject   string `json:"sub"`
	Email     string `json:"email"`
	Issuer    string `json:"iss"`
	Audience  any    `json:"aud"`
	ExpiresAt int64  `json:"exp"`
	NotBefore int64  `json:"nbf"`
}
type header struct {
	Algorithm string `json:"alg"`
	KeyID     string `json:"kid"`
}

func (v *Verifier) Verify(token string) (User, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return User{}, errors.New("auth: malformed jwt")
	}
	var h header
	if err := decode(parts[0], &h); err != nil {
		return User{}, err
	}
	key, ok := v.keys[h.KeyID]
	if !ok {
		return User{}, errors.New("auth: unknown jwt key")
	}
	if err := verifySignature(key, h.Algorithm, parts[0]+"."+parts[1], parts[2]); err != nil {
		return User{}, err
	}
	var c claims
	if err := decode(parts[1], &c); err != nil {
		return User{}, err
	}
	now := v.now().Unix()
	if c.Subject == "" || c.Issuer != v.issuer || !audienceMatches(c.Audience, v.audience) || c.ExpiresAt <= now || (c.NotBefore != 0 && c.NotBefore > now) {
		return User{}, errors.New("auth: invalid jwt claims")
	}
	return User{ID: c.Subject, Email: c.Email}, nil
}

func decode(segment string, value any) error {
	b, err := base64.RawURLEncoding.DecodeString(segment)
	if err != nil {
		return err
	}
	return json.Unmarshal(b, value)
}
func audienceMatches(value any, expected string) bool {
	switch aud := value.(type) {
	case string:
		return aud == expected
	case []any:
		for _, item := range aud {
			if s, ok := item.(string); ok && s == expected {
				return true
			}
		}
	}
	return false
}
func rsaPublicKey(nValue, eValue string) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(nValue)
	if err != nil {
		return nil, err
	}
	eBytes, err := base64.RawURLEncoding.DecodeString(eValue)
	if err != nil {
		return nil, err
	}
	e := 0
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}
	return &rsa.PublicKey{N: new(big.Int).SetBytes(nBytes), E: e}, nil
}

func ecdsaPublicKey(curveName, xValue, yValue string) (*ecdsa.PublicKey, error) {
	if curveName != "P-256" {
		return nil, errors.New("auth: unsupported elliptic curve")
	}
	x, err := base64.RawURLEncoding.DecodeString(xValue)
	if err != nil {
		return nil, err
	}
	y, err := base64.RawURLEncoding.DecodeString(yValue)
	if err != nil {
		return nil, err
	}
	curve := elliptic.P256()
	pub := &ecdsa.PublicKey{Curve: curve, X: new(big.Int).SetBytes(x), Y: new(big.Int).SetBytes(y)}
	if !curve.IsOnCurve(pub.X, pub.Y) {
		return nil, errors.New("auth: invalid elliptic jwk")
	}
	return pub, nil
}

func verifySignature(key crypto.PublicKey, algorithm, signingInput, encodedSignature string) error {
	signature, err := base64.RawURLEncoding.DecodeString(encodedSignature)
	if err != nil {
		return err
	}
	digest := sha256.Sum256([]byte(signingInput))
	switch algorithm {
	case "RS256":
		pub, ok := key.(*rsa.PublicKey)
		if !ok {
			return errors.New("auth: key does not match jwt algorithm")
		}
		return rsa.VerifyPKCS1v15(pub, crypto.SHA256, digest[:], signature)
	case "ES256":
		pub, ok := key.(*ecdsa.PublicKey)
		if !ok || len(signature) != 64 {
			return errors.New("auth: invalid es256 signature")
		}
		r, s := new(big.Int).SetBytes(signature[:32]), new(big.Int).SetBytes(signature[32:])
		if !ecdsa.Verify(pub, digest[:], r, s) {
			return errors.New("auth: invalid jwt signature")
		}
		return nil
	default:
		return errors.New("auth: unsupported jwt algorithm")
	}
}
