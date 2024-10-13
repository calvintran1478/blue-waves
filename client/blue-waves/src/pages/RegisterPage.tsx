import { createSignal } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { HTTPError } from "ky";
import ky from "ky";

const RegisterPage = () => {
    const [email, setEmail] = createSignal("");
    const [password, setPassword] = createSignal("");
    const [firstName, setFirstName] = createSignal("");
    const [lastName, setLastName] = createSignal("");

    const navigate = useNavigate();

    const registerUser = async (event: Event) => {
        // Prevent refresh
        event.preventDefault();

        try {
            // Register user
            await ky.post("http://localhost:8080/api/v1/users", {
                json: {
                    email: email(),
                    password: password(),
                    first_name: firstName(),
                    last_name: lastName()
                }
            })

            // Navigate to login page
            navigate("/login");

        } catch(error) {
            // Cast error to appropriate type
            const httpError = error as HTTPError;

            // Handle error based on status code
            if (httpError.response.status === 400) {
                console.log("400!");
            } else if (httpError.response.status === 409) {
                console.log("409!");
            }
        }
    }

    return (
        <div class="flex justify-center items-center w-screen h-screen">
            <div class="flex flex-col items-center border-2 p-10" style="width: 40rem; height: 42rem;">
                <h1 class="text-2xl font-bold mb-4">Register</h1>
                <form onSubmit={registerUser} class="flex flex-col items-center">
                    <div class="flex flex-col m-4 text-xl">
                        <label for="email">Email</label>
                        <input id="email" type="email" class="border-2 w-96 h-10" onChange={(event) => setEmail(event.target.value)} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="password">Password</label>
                        <input id="password" type="password" class="border-2 w-96 h-10" onChange={(event) => setPassword(event.target.value)} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="firstName">First Name</label>
                        <input id="firstName" class="border-2 w-96 h-10" onChange={(event) => setFirstName(event.target.value)} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="lastName">Last Name</label>
                        <input id="lastName" class="border-2 w-96 h-10" onChange={(event) => setLastName(event.target.value)} required/>
                    </div>
                    <button class="border-2 rounded p-2 mt-8 text-lg">Create Account</button>
                </form>
            </div>
        </div>
    )
}

export default RegisterPage;
