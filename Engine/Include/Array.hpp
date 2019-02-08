#pragma once

#include <string.h>

template< typename T > struct Array
{
    Array() {}
    
    explicit Array( int elementCount ) { Allocate( elementCount );  }

    Array( const Array<T>& other ) { *this = other; }

    ~Array()
    {
        delete[] elements;
        elements = nullptr;
        count = 0;
    }
    
    Array<T>& operator=( const Array<T>& other )
    {
        if (this == &other)
        {
            return *this;
        }
        
        delete[] elements;
        count = other.count;
        elements = new T[ count ];

        for ( unsigned i = 0; i < count; ++i)
        {
            elements[ i ] = other.elements[ i ];
        }

        return *this;
    }
    
    T& operator[]( unsigned index ) { return elements[ index ]; }

    const T& operator[]( unsigned index ) const { return elements[ index ]; }
    
    void Add( const T& item )
    {
        T* after = new T[ count + 1 ]();
        
        for ( unsigned i = 0; i < count; ++i)
        {
            after[ i ] = elements[ i ];
        }

        after[ count ] = item;
        delete[] elements;
        elements = after;
        count = count + 1;
    }
    
    void Allocate( unsigned size )
    {
        if (count == size)
        {
            return;
        }
        
        delete[] elements;
        elements = size > 0 ? new T[ size ]() : nullptr;
        count = size;
    }
    
    T* elements = nullptr;
	unsigned count = 0;
};

