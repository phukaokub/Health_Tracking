package auth

import (
	"crypto"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
)

func verifyRS256(key *rsa.PublicKey, signingInput, encodedSignature string) error {
	sig, err := base64.RawURLEncoding.DecodeString(encodedSignature)
	if err != nil {
		return err
	}
	digest := sha256.Sum256([]byte(signingInput))
	return rsa.VerifyPKCS1v15(key, crypto.SHA256, digest[:], sig)
}
