package auth

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
)

func FetchJWKS(ctx context.Context, endpoint string) (JWKS, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return JWKS{}, err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return JWKS{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return JWKS{}, fmt.Errorf("auth: jwks request returned %s", response.Status)
	}
	var jwks JWKS
	if err := json.NewDecoder(response.Body).Decode(&jwks); err != nil {
		return JWKS{}, err
	}
	return jwks, nil
}
