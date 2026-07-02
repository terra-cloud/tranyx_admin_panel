const { initializeApp } = require("firebase/app");
const { getFirestore, collection, getDocs, limit, query } = require("firebase/firestore");

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

async function inspectCollection(name) {
  try {
    const q = query(collection(db, name), limit(3));
    const querySnapshot = await getDocs(q);
    console.log(`\n=== Collection: ${name} (${querySnapshot.size} documents) ===`);
    querySnapshot.forEach((doc) => {
      console.log(doc.id, " => ", JSON.stringify(doc.data(), null, 2));
    });
  } catch (err) {
    console.error(`Error reading ${name}: `, err);
  }
}

async function run() {
  await inspectCollection("users");
  await inspectCollection("transactions");
  await inspectCollection("jobs");
  await inspectCollection("rentals");
  await inspectCollection("properties");
  await inspectCollection("kyc_submissions");
  await inspectCollection("supportTickets");
}

run();
