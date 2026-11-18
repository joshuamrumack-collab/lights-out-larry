# Class leaderboard (Google Sheets)

Scores go into a Google Sheet that you own. There's no server to run and no accounts for students.

1. Create a new Google Sheet, for example "OneBeat scores".
2. In the sheet, choose **Extensions → Apps Script**. Delete what's there and paste in `Code.gs` from this folder. Save.
3. Optional class code: open **Project Settings → Script properties** and add `CLASS_CODE` with any word. Only games that have that code can post scores.
4. Choose **Deploy → New deployment → Web app**:
   - Execute as: **Me**
   - Who has access: **Anyone**
   Then approve the permissions and copy the **Web app URL** (it ends in `/exec`).
5. In the game, go to **Settings → Class leaderboard**, paste the URL and the class code, and enter a player name.
   For the browser build, put the URL and code in `config/leaderboard.cfg` *before* exporting, so students don't have to type them.

Each student's best score per song and difficulty shows on the board, per week (and all time). Scores played
with assist or eye tracker mode are marked. You can delete rude names or bad rows straight in the sheet.
