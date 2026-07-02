const { initializeApp } = require("firebase/app");
const { getFirestore, collection, getDocs } = require("firebase/firestore");

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

async function check() {
  try {
    const querySnapshot = await getDocs(collection(db, "users"));
    console.log("Found " + querySnapshot.size + " users:");
    querySnapshot.forEach((doc) => {
      console.log(doc.id, " => ", JSON.stringify(doc.data()));
    });
  } catch (err) {
    console.error("Error reading: ", err);
  }
}
check();
