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
        <>
            <h1>Register</h1>
            <form onSubmit={registerUser}>
            <div>
                <label for="email"> </label>
                <input id="email" type="email" onChange={(event) => setEmail(event.target.value)} required/>
            </div>
            <div>
                <label for="password"> </label>
                <input id="password" type="password" onChange={(event) => setPassword(event.target.value)} required/>
            </div>
            <div>
                <label for="firstName"> </label>
                <input id="firstName" onChange={(event) => setFirstName(event.target.value)} required/>
            </div>
            <div>
                <label for="lastName"> </label>
                <input id="lastName" onChange={(event) => setLastName(event.target.value)} required/>
            </div>
            <button>Create Account</button>
            </form>
        </>
    )
}

export default RegisterPage;
