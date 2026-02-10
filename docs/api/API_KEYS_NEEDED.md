# 🔑 API Keys Needed for OCR System

## Quick Checklist

- [ ] **Gemini API Key** (for AI-powered brand normalization)
- [ ] **Google Vision API Credentials** (for text extraction from images)

---

## 1. Gemini API Key (FREE!)

### How to Get It:
1. Visit: **https://makersuite.google.com/app/apikey**
2. Sign in with your Google account
3. Click **"Create API Key"**
4. Copy the key (starts with `AIza...`)

### Where to Add It:
```bash
# Edit this file:
/var/www/liquorpro/.env.production

# Find this line:
GEMINI_API_KEY=YOUR_GEMINI_API_KEY_HERE

# Replace with your actual key:
GEMINI_API_KEY=AIzaSyDxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

### Free Tier Limits:
- ✅ 60 requests per minute
- ✅ 1,500 requests per day
- ✅ Perfect for invoice processing!

---

## 2. Google Cloud Vision API Credentials

### How to Get It:
1. Go to: **https://console.cloud.google.com/apis/credentials**
2. Create a new project or select existing
3. Enable **"Cloud Vision API"**
4. Create a **Service Account**:
   - Click "Create Credentials" → "Service Account"
   - Name it: `liquorpro-vision-api`
   - Role: "Cloud Vision AI Service Agent"
5. Download the JSON key file

### Where to Place It:
```bash
# Upload your downloaded JSON file to this exact location:
/var/www/liquorpro/credentials/google-vision-credentials.json

# Set permissions:
sudo chmod 600 /var/www/liquorpro/credentials/google-vision-credentials.json
sudo chown root:root /var/www/liquorpro/credentials/google-vision-credentials.json
```

### Free Tier Limits:
- ✅ First 1,000 images/month: FREE
- ✅ After that: $1.50 per 1,000 images
- ✅ Very affordable!

---

## Quick Commands to Set Up

```bash
# 1. Edit environment file
sudo nano /var/www/liquorpro/.env.production
# Add your GEMINI_API_KEY

# 2. Upload Vision credentials
sudo mkdir -p /var/www/liquorpro/credentials
sudo cp /path/to/your-credentials.json \
       /var/www/liquorpro/credentials/google-vision-credentials.json
sudo chmod 600 /var/www/liquorpro/credentials/google-vision-credentials.json

# 3. Rebuild and restart services
cd /var/www/liquorpro
docker-compose -f docker-compose.production.yml build sales
docker-compose -f docker-compose.production.yml up -d sales gateway

# 4. Verify it's working
docker logs liquorpro-sales-prod --tail 50
```

---

## ✅ Verification

After adding both keys, you should see:
```
✅ Sales service starting on 0.0.0.0:8092
✅ No errors about GEMINI_API_KEY
✅ No errors about GOOGLE_APPLICATION_CREDENTIALS
✅ OCR endpoints ready at /api/sales/ocr/*
```

---

## 💰 Monthly Cost Estimate

For **10,000 invoices per month**:
- Gemini AI: **$0** (free tier)
- Vision API: **~$15** (after first 1,000 free)

**Total: ~$15/month** for unlimited accuracy! 🎯
