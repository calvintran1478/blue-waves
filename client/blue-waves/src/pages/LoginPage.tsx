import { createSignal } from "solid-js";
import { useNavigate } from "@solidjs/router";
import { HTTPError } from "ky";
import ky from "ky";

const LoginPage = () => {
    const [email, setEmail] = createSignal("");
    const [password, setPassword] = createSignal("");

    const navigate = useNavigate();

    const loginUser = async (event: Event) => {
        // Prevent refresh
        event.preventDefault();

        try {
            // Login user
            await ky.post("http://localhost:8080/api/v1/users/login", {
                json: {
                    email: email(),
                    password: password()
                }
            })

            // Navigate to home page
            navigate("/home");

        } catch (error) {
            // Cast error to appropriate type
            const httpError = error as HTTPError;

            // Handle error based on status code
            if (httpError.response.status === 401) {
                console.log("Wrong password");
            } else if (httpError.response.status === 404) {
                console.log("Account not found");
            }
        }
    }

    return (
        <div class="flex justify-center items-center w-screen h-screen">
            <div class="flex flex-col items-center border-2 p-10" style="width: 40rem; height: 30rem;">
                <h1 class="text-2xl font-bold mb-4">Login</h1>
                <form onSubmit={loginUser} class="flex flex-col items-center">
                    <div class="flex flex-col m-4 text-xl">
                        <label for="email">Email</label>
                        <input id="email" type="email" class="border-2 w-96 h-10" onChange={(event) => setEmail(event.target.value)} required/>
                    </div>
                    <div class="flex flex-col m-4 text-xl">
                        <label for="password">Password</label>
                        <input id="password" type="password" class="border-2 w-96 h-10" onChange={(event) => setPassword(event.target.value)} required/>
                    </div>
                    <button class="border-2 rounded px-10 py-2 mt-10 text-lg">Login</button>
                </form>
            </div>
        </div>
    )
}

export default LoginPage;