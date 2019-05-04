using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class RandomForce : MonoBehaviour
{
    private Rigidbody _rigidbody;
    void Start()
    {
        _rigidbody = GetComponent<Rigidbody>();
        InvokeRepeating("UseForce",Random.Range(0,1),Random.Range(0.1f,1));
    }

    void Update()
    {
    }

    void UseForce()
    {
        _rigidbody.AddForce(new Vector3(Random.Range(-10,10),Random.Range(-10,10),Random.Range(-10,10)),ForceMode.Impulse);
    }
}