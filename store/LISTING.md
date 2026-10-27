# Alma: App Store listing (draft)

Paste-ready text for App Store Connect. Character limits checked; counts in brackets.
Everything here matches the privacy policy at https://almapic.com/privacy (branch
`appstore-prep` of gen-seller; it is live only after the frontend is deployed).

## App information

| Field | Value |
|---|---|
| Bundle ID | `com.arielhalevy.alma` (recommended; see the end of this file) |
| SKU | `alma-ios-001` |
| Primary language | English (U.S.); add Hebrew as a second localization |
| Primary category | Lifestyle |
| Secondary category | Shopping |
| Price | Free, no in-app purchases |
| Availability | Israel (products, prices and retailers are Israeli). Add more countries when there is local inventory. |
| Privacy Policy URL | https://almapic.com/privacy |
| Support URL | https://almapic.com/support |
| Marketing URL (optional) | https://almapic.com |
| Copyright | 2026 Ariel Halevy |

## English (U.S.)

**Name** [22/30]
```
Alma: AI Room Redesign
```

**Subtitle** [29/30]
```
Redesign rooms, shop the look
```

**Promotional text** [129/170]
```
Photograph a room and see it redesigned in about a minute, furnished with real pieces you can buy today from Israeli home stores.
```

**Description**
```
Alma turns a photo of your room into a redesign you can actually buy.

Choose a photo, tell Alma what the room is and how you want it to feel, and in about a minute you get a redesigned version of your own space. Every piece in the picture is a real, in-stock product from an Israeli home retailer, with its price and a link to the store.

HOW IT WORKS
• Pick a photo of your room. A single wide shot in daylight works best.
• Choose the room type and a palette: warm neutrals, cool greys, earthy greens, bold accents, light and airy, or let Alma surprise you.
• Add a note if you like, such as "keep the sofa" or "add plants".
• See your room redesigned. Press and hold the image to compare with the original.
• Tap any product to open it on the retailer's site.

WHY ALMA
• Your room, not a stock photo. The redesign keeps your walls, windows and layout.
• Real furniture, real prices in shekels, from local stores.
• No account needed. Signing in with Apple or Google is optional, and you can delete your account in the app at any time.
• Full Hebrew and English support, right to left.

PRIVACY
Before your first redesign, Alma asks your permission to send the photo for AI processing. The app only sees the photo you choose. No ads, no tracking. Details: almapic.com/privacy
```

**Keywords** [96/100]
```
interior design,home decor,furniture,room planner,AI design,makeover,living room,shopping,Israel
```

**What's New** (not shown for a first version; keep for 1.0.1)
```
First release.
```

## Hebrew (he)

**Name** [21/30]
```
Alma: עיצוב חדר עם AI
```

**Subtitle** [28/30]
```
עצבו את החדר, קנו את הרהיטים
```

**Promotional text** [95/170]
```
צלמו חדר וראו אותו מעוצב מחדש תוך דקה, עם רהיטים אמיתיים שאפשר לקנות היום מחנויות בית ישראליות.
```

**Description**
```
Alma הופכת תמונה של החדר שלכם לעיצוב חדש שאפשר באמת לקנות.

בחרו תמונה, ספרו ל-Alma איזה חדר זה ואיזו תחושה אתם רוצים, ותוך כדקה תקבלו גרסה מעוצבת מחדש של החלל שלכם. כל פריט בתמונה הוא מוצר אמיתי שזמין במלאי בחנות בית ישראלית, עם מחיר וקישור לחנות.

איך זה עובד
• בחרו תמונה של החדר. צילום רחב אחד באור יום עובד הכי טוב.
• בחרו את סוג החדר ופלטת צבעים: ניטרלים חמים, אפורים קרירים, ירוקים אדמתיים, צבעי דגש, בהיר ואוורירי, או תנו ל-Alma להפתיע.
• הוסיפו הערה אם תרצו, למשל "השאירו את הספה" או "הוסיפו צמחים".
• ראו את החדר מעוצב מחדש. לחיצה ארוכה על התמונה מציגה את המקור להשוואה.
• הקישו על מוצר כדי לפתוח אותו באתר החנות.

למה Alma
• החדר שלכם, לא תמונת מאגר. העיצוב שומר על הקירות, החלונות והמבנה.
• רהיטים אמיתיים, מחירים בשקלים, מחנויות מקומיות.
• אין צורך בחשבון. התחברות עם Apple או Google היא אופציונלית, ואפשר למחוק את החשבון באפליקציה בכל עת.
• תמיכה מלאה בעברית ובאנגלית, מימין לשמאל.

פרטיות
לפני העיצוב הראשון, Alma מבקשת רשות לשלוח את התמונה לעיבוד AI. האפליקציה רואה רק את התמונה שבחרתם. אין פרסומות ואין מעקב. פרטים: almapic.com/privacy
```

**Keywords** [72/100] (no other brands' names: guideline 2.3.7)
```
עיצוב פנים,עיצוב הבית,רהיטים,עיצוב חדר,סלון,חדר שינה,AI,שיפוץ,קניות,מטבח
```

## Screenshots

`store/screenshots/en/` and `store/screenshots/he/`, five each, 1320 x 2868 PNG
(6.9-inch display, iPhone 16 Pro Max simulator, no alpha channel). Upload them to the
6.9" slot; App Store Connect scales them down for smaller iPhones. No iPad set is
needed because the app is iPhone-only.

1. Sign in (Apple, Google, or "Continue without an account")
2. Your room (photo chosen)
3. The look (room + palette)
4. Review
5. Result with buyable products (real output from the production backend)

The sample room photo is `frontend/public/examples/living-room.jpg` from the web repo.
Confirm you have the right to use it commercially, or retake the set with a photo of
your own room (see the README for the launch arguments).

## Age rating questionnaire

Answer **None / No** to everything:

| Question | Answer |
|---|---|
| Parental controls / age assurance | No |
| Unrestricted web access | No (product links open Safari outside the app) |
| User-generated content shared with other users | No (notes go only to the AI; nothing is shown to other people) |
| Messaging and chat | No |
| Advertising | No |
| Violence, sexual content, nudity, profanity, horror, drugs, alcohol, tobacco, gambling, contests, medical/wellness topics | None |

Expected result: **4+**.

## App Privacy ("nutrition label")

**Tracking:** No. The app does not track users and has no advertising or analytics SDK.

**Data collected** (all purposes: *App Functionality* only; none used for tracking):

| Data type (Apple's name) | Collected | Linked to the user | Why |
|---|---|---|---|
| Photos or Videos | Yes | Yes | The room photo is sent for the redesign. Linked because, for signed-in users, the diagnostic record carries the account id. |
| Other User Content | Yes | Yes | The optional note typed for the redesign. |
| Name | Yes | Yes | Only if the user signs in and shares it with Apple. |
| Email Address | Yes | Yes | Only if the user signs in (may be an Apple private-relay address). |
| User ID | Yes | Yes | The Apple account identifier and Alma's account id. |

Not collected: location, contacts, health, financial info, browsing/search history,
purchases (the purchase happens on the retailer's site), device ID, crash or
performance data, advertising data.

Note on "Optional" disclosure: Apple only lets you skip data that is collected
rarely and optionally. Photos are core to the app, so declare them.

## App Review information

**Sign-in required:** No. Leave the demo account fields empty.

**Notes for the reviewer** (paste):
```
No account is needed. On the first screen tap "Continue without an account".

Flow: choose any room photo, pick a room type and palette, tap Review, then "Redesign my room". The first time, the app asks permission to send the photo to its server for AI processing (OpenAI and Google); tap "Agree and continue". Generating the redesign takes about a minute. Product names are in Hebrew because the products come from Israeli retailers; tapping a product opens the retailer's website in Safari. There is no in-app purchase.

Signing in is optional (Sign in with Apple or Google). Account deletion: tap the person icon at the top of the first step, then "Delete account".

Privacy policy and support are linked from the first screen and from the account menu.
```

**Contact:** Ariel Halevy, phone and email of your choice.

## Export compliance

Answered in the binary: `ITSAppUsesNonExemptEncryption = NO` (HTTPS only, via Apple's
frameworks). App Store Connect will not ask.

## Content rights

App Store Connect asks whether the app "contains, shows, or accesses third-party
content". **Yes**: product names, prices and photos come from retailer websites.
Guideline 5.2.2 requires permission to use them. Answer honestly and be ready to show
that the retailers allow it (terms of use, an affiliate agreement, or written
permission).

## Bundle ID recommendation

Use **`com.arielhalevy.alma`**, not `com.arielhalevy.alma.swift`. The Expo build never
shipped, so the clean id is free, and a bundle id cannot be changed once an App Store
Connect record exists. The `.swift` suffix only existed so both builds could sit on one
phone. To switch: in Xcode, target Alma, Signing & Capabilities, Bundle Identifier; also
change the test target to `com.arielhalevy.alma.tests`. The backend already accepts
Apple tokens for both ids (`APPLE_BUNDLE_IDS`).
