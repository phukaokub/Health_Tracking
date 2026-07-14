package auth

import (
	"context"
	"crypto/rsa"
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
}

type Verifier struct {
	issuer   string
	audience string
	keys     map[string]*rsa.PublicKey
	now      func() time.Time
}

func NewVerifier(issuer, audience string, jwks JWKS) (*Verifier, error) {
	keys := map[string]*rsa.PublicKey{}
	for _, key := range jwks.Keys {
		if key.Kty != "RSA" || key.N == "" || key.E == "" || key.Kid == "" {
			continue
		}
		pub, err := rsaPublicKey(key.N, key.E)
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
	if h.Algorithm != "RS256" {
		return User{}, errors.New("auth: unsupported jwt algorithm")
	}
	key, ok := v.keys[h.KeyID]
	if !ok {
		return User{}, errors.New("auth: unknown jwt key")
	}
	if err := verifyRS256(key, parts[0]+"."+parts[1], parts[2]); err != nil {
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
