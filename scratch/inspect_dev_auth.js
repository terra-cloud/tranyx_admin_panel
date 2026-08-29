const { initializeApp } = require("firebase/app");
const { getAuth, signInWithEmailAndPassword } = require("firebase/auth");
const { getFirestore, collection, getDocs, limit, query, doc, getDoc } = require("firebase/firestore");

const firebaseConfig = {
  apiKey: "AIzaSyDyIwtMC_ssjILT0tAdtLVf8M4qc7L3ijU",
  authDomain: "tranyx-dev.firebaseapp.com",
  projectId: "tranyx-dev",
  storageBucket: "tranyx-dev.firebasestorage.app",
  messagingSenderId: "709467070093",
  appId: "1:709467070093:web:4d38bcfda904b0d5df4cc4",
};

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);

async function run() {
  try {
    const cred = await signInWithEmailAndPassword(auth, "admin@tranyx.app", "admin123456");
    console.log("Logged in as:", cred.user.email, cred.user.uid);

    console.log("=== DEPOSIT REQUESTS ===");
    const depSnap = await getDocs(query(collection(db, "deposit_requests"), limit(3)));
    depSnap.forEach((d) => console.log("DEP:", d.id, "=>", JSON.stringify(d.data())));

    console.log("=== USERS ===");
    const userSnap = await getDocs(query(collection(db, "users"), limit(3)));
    userSnap.forEach((d) => console.log("USER:", d.id, "=>", JSON.stringify(d.data())));

    console.log("=== WALLETS ===");
    try {
      const wallSnap = await getDocs(query(collection(db, "wallets"), limit(3)));
      wallSnap.forEach((d) => console.log("WALLET:", d.id, "=>", JSON.stringify(d.data())));
    } catch (e) {
      console.log("No wallets collection");
    }
  } catch (e) {
    console.error("Auth error:", e);
  }
}
run();
