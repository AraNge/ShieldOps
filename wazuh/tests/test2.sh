TOKEN=$(curl -k -u "${API_USERNAME}:${API_PASSWORD}" "https://localhost:55000/security/user/authenticate?raw=true")
curl -k -X GET "https://localhost:55000/agents" -H "Authorization: Bearer $TOKEN"
