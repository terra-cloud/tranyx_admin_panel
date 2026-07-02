const { initializeApp } = require("firebase/app");
const { getFirestore, collection, getDocs, doc } = require("firebase/firestore");

const firebaseConfig = {
  apiKey: "AIzaSyDyIwtMC_ssjILT0tAdtLVf8M4qc7L3ijU",
  authDomain: "tranyx-dev.firebaseapp.com",
  projectId: "tranyx-dev",
  storageBucket: "tranyx-dev.firebasestorage.app",
  messagingSenderId: "709467070093",
  appId: "1:709467070093:web:4d38bcfda904b0d5df4cc4",
};

const app = initializeApp(firebaseConfig);
const db = getFirestore(app);

// In Firebase Client SDK, we can't directly list subcollections of a doc, but we can query known subcollection names
// Let's try loading from typical names: "qna", "questions", "comments", "messages", "answers"
async function checkDocSubcollections(colName, docId) {
  const targets = ["qna", "questions", "comments", "messages", "answers", "public_qna"];
  console.log(`\nChecking doc: /${colName}/${docId}`);
  for (const t of targets) {
    try {
      const snap = await getDocs(collection(db, colName, docId, t));
      if (snap.size > 0) {
        console.log(`  Found subcollection "${t}" with ${snap.size} documents:`);
        snap.forEach(d => {
          console.log(`    ${d.id} => ${JSON.stringify(d.data())}`);
        });
      }
    } catch (e) {
      console.log(`  Error checking "${t}": ${e.message}`);
    }
  }
}

async function run() {
  // Let's check some known doc IDs from our previous dump
  await checkDocSubcollections("jobs", "9ZXM2xjih4JaLv2NFSza");
  await checkDocSubcollections("rentals", "JccmzmPtoGhmugIoGXvn");
  await checkDocSubcollections("properties", "Ew4JF96HBZnTG6MdL0i7");
}

run();
