# TOKEN ALMA REHBERİ

## NPM Token (npm publish için)

1. Tarayıcıda aç: https://www.npmjs.com
2. Oturum aç (sign in)
3. Profile tıkla → Access Tokens
4. Create New Token
5. Name: `oh-my-opencode`
6. Type: Automation
7. Generate
8. Token'ı kopyala

---

## GitHub Token (GitHub Actions için)

1. Tarayıcıda aç: https://github.com/settings/tokens
2. Generate new token (classic)
3. Note: `oh-my-opencode`
4. Expiration: No expiration
5. Select scopes: ✓ repo, ✓ workflow
6. Generate token
7. Token'ı kopyala

---

## TOKENI VERDİĞİNDA

```bash
# NPM için
echo "//registry.npmjs.org/:_authToken=TOKEN" > ~/.npmrc
npm publish --access public

# Veya GitHub secret olarak ekle
gh secret set NPM_TOKEN
```

---

## DOSYALAR HAZIR

```
D:\OpenCode\oh-my-opencode\dev\oh-my-opencode-dev\
├── dist\                    ✅ Build (2.53 MB)
├── package.json            ✅ v3.8.0
└── publish.sh              ✅ Script
```

---

Token'ı aldığında söyle, hemen ekleyip publish ederim!
