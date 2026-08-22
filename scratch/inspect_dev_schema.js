const { initializeApp } = require("firebase/app");
const { getFirestore, collection, getDocs, limit, query, getDoc, doc } = require("firebase/firestore");

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

async function inspectDev() {
  try {
    console.log("=== DEPOSIT REQUESTS ===");
    const depSnap = await getDocs(query(collection(db, "deposit_requests"), limit(5)));
    depSnap.forEach((d) => console.log(d.id, " => ", JSON.stringify(d.data())));

    console.log("=== USERS ===");
    const userSnap = await getDocs(query(collection(db, "users"), limit(5)));
    userSnap.forEach((d) => console.log(d.id, " => ", JSON.stringify(d.data())));

    console.log("=== WALLETS ===");
    try {
      const wallSnap = await getDocs(query(collection(db, "wallets"), limit(5)));
      wallSnap.forEach((d) => console.log(d.id, " => ", JSON.stringify(d.data())));
    } catch (e) {
      console.log("Wallets query notice:", e.message);
    }
  } catch (err) {
    console.error("Error reading: ", err);
  }
}
inspectDev();
