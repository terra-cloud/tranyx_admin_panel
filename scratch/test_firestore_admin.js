const { initializeApp } = require("firebase/app");
const { getFirestore, collection, getDocs } = require("firebase/firestore");

const firebaseConfig = {
  apiKey: "AIzaSyDmDFdlZCOBzDYx5EsZoy8Gw9mnBVtPNj0",
  authDomain: "tranyx-admin-portal.firebaseapp.com",
  projectId: "tranyx-admin-portal",
  storageBucket: "tranyx-admin-portal.firebasestorage.app",
  messagingSenderId: "998364264423",
  appId: "1:998364264423:web:f32052956a463360996f42",
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
